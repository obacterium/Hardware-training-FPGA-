# 俄罗斯方块软件构建与验证

## 第 1 阶段 RARS 原型

终端版中大写字符表示已锁定的方块，小写字符表示活动方块。输入一个命令后按 Enter。`A/D` 左右移动，`W` 旋转，`S` 软降，`H` 或空格硬降，`P` 暂停或恢复，`R` 重开，`Q` 退出。`T` 或空行让模拟时间前进 100 ms，便于逐步查看重力效果。

在 `team work` 目录运行，按本机安装位置设置 `$RarsJar` 与 `$JavaExe`。

```powershell
$stage = Join-Path (Get-Location).Path 'Hardware-training-FPGA-/software/tetris/stage1'
$RarsJar = 'D:\tools\rars.jar'
$JavaExe = 'java'
$sources = 'rars_play.s', 'game.s', 'tables.s' | ForEach-Object { Join-Path $stage $_ }
& $JavaExe '-Djava.awt.headless=true' -jar $RarsJar nc ae1 se2 sm @sources
```

运行固定输入回归时，在同一个 PowerShell 会话执行以下命令。最后一条验收输出为 `PASS: all stage1 game tests`。

```powershell
& (Join-Path $stage 'test.ps1') -RarsJar $RarsJar -Java $JavaExe
```

`game_init` 接收状态区、方块表、方块序列地址、非零序列长度和初始毫秒数。方块 ID `0–6` 对应 `I/O/T/S/Z/J/L`，序列循环使用。`game_step` 接收状态区、接口约定中的逻辑键码和当前毫秒数，每次至多结算一个方块。`layout.inc` 定义棋盘和状态的偏移，棋盘中 `0` 是空格，`1–7` 是对应的已锁定方块。终端输入输出的 RARS 系统调用集中在 `rars_play.s`。

## 第 0 阶段启动自检

使用 RARS 汇编 RV32 程序。`stage0/ram_probe.s` 是共用的 RAM 自检，`rars_smoke.s` 是 RARS 测试入口，`fpga_smoke.s` 是从 PC=0 启动的 FPGA 入口。FPGA 版通过 MMIO LED 报告自检结果。

### 构建镜像

在 PowerShell 中进入 `team work` 目录，将示例中的 RARS 和 Vivado 路径设为本机实际位置。`$JavaExe` 也可填写 `java.exe` 的绝对路径。

```powershell
$teamDir = (Get-Location).Path
$repo = Join-Path $teamDir 'Hardware-training-FPGA-'
$stage = Join-Path $repo 'software/tetris/stage0'
$runDir = Join-Path $teamDir 'stage0-run'
$RarsJar = 'D:\tools\rars.jar'
$JavaExe = 'java'
$VivadoBin = 'D:\Xilinx\Vivado\2022.1\bin'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
& (Join-Path $stage 'build.ps1') -RarsJar $RarsJar -Java $JavaExe `
    -ImagePath (Join-Path $runDir 'stage0.mem')
```

构建先运行 RARS 自检，要求控制台输出 `PASS: stage0 RAM probe` 并以状态 0 结束。随后用 `CompactTextAtZero` 导出 FPGA `.text`，每行一个 32 位十六进制指令字。当前内核以 4096 个字为上限，镜像首字 `00008137` 对应 `lui sp, 0x8`。脚本输出指令字数和 SHA-256，可用两次构建的哈希检查一致性。

### 运行独立 RTL 仿真

沿用上一步的 PowerShell 变量。在 `$runDir` 载入 `stage0.mem`，使用现有的重定向流水线内核做行为仿真。

```powershell
$sources = Join-Path $repo 'riscv-cpu/riscv-cpu.srcs/sources_1/new'
$rtl = @(Get-ChildItem -LiteralPath "$sources/RiscVCPU", "$sources/peripherals" `
    -Recurse -Filter '*.v' -File | Select-Object -ExpandProperty FullName)

Push-Location -LiteralPath $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv @rtl (Join-Path $stage 'stage0_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & (Join-Path $VivadoBin 'xelab.bat') --mt off work.stage0_tb -s stage0_rtl
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    & (Join-Path $VivadoBin 'xsim.bat') stage0_rtl -runall
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
} finally {
    Pop-Location
}
```

以控制台三条 `PASS` 为验收依据。测试台会检查 PC=0 的首条指令、首次有效写回 `x2=0x00008000`、RAM 中的三个预期数据以及 `SYS_ID` 读取后 MMIO LED 的 `0x600D`。自检的故障指示分别为 `0x0101`（RAM）和 `0x0102`（`SYS_ID`）。

## FPGA 数据 RAM 布局

| 地址范围 | 用途 |
| --- | --- |
| `0x0000–0x00FF` | 预留给 10×20 棋盘，每格 1 字节 |
| `0x0100–0x01FF` | 预留给游戏状态、计时、PS/2 解码状态和软件按键队列 |
| `0x0200–0x15FF` | 预留给渲染数据，空间可容纳 4800 字节字符缓冲 |
| `0x7000–0x7007` | 第 0 阶段 RAM 自检区 |
| `0x7800–0x7FFF` | 栈区，从初始 `sp=0x8000` 向低地址增长 |

第 0 阶段实际写入自检区和栈。游戏版启动代码应初始化实际使用的 RAM 区域，RARS 测试入口使用 RARS 自身的数据段和栈地址。

## 当前内核的指令旁路

当前 RTL 将 `LUI` 的立即数在写回阶段送入寄存器。EX 旁路取的是 ALU 结果，紧邻的依赖指令可能读到不同的值。第 0 阶段在这类 `LUI` 与使用者之间安排了两条独立指令，使使用者走 WB 旁路。汇编伪指令 `li` 可能展开为相邻的 `lui` 和 `addi`，后续生成 FPGA 镜像时应在已修复的内核上验证这类指令序列，或检查相关汇编的指令间距。
