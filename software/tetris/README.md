# 俄罗斯方块软件构建与验证

## FPGA 镜像

从 `team work` 目录运行。使用课程 RARS JAR 和本机 Java。构建器在 RARS 默认配置中汇编 `.text`，取出的首指令字装入 FPGA 的 PC=0。分支与调用使用相对位移，RAM 和 MMIO 使用显式地址。上电代码逐字初始化方块、颜色和文字表，当前指令 ROM 上限为 4096 字。

```powershell
$teamDir = (Get-Location).Path
$repo = Join-Path $teamDir 'Hardware-training-FPGA-'
$firmware = Join-Path $repo 'software/tetris/stage3'
$runDir = Join-Path $teamDir 'stage23-run'
$RarsJar = 'D:\tools\rars.jar'
$JavaExe = 'java'
$VivadoBin = 'D:\Xilinx\Vivado\2022.1\bin'

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
& (Join-Path $firmware 'build.ps1') -RarsJar $RarsJar -Java $JavaExe -OutputDirectory $runDir
```

| 镜像 | 上板后依次核对的现象 |
| --- | --- |
| `diag_mmio.mem` | `SW[15]=1` 时 LED 镜像拨码。`SW[2:0]=111` 选 MMIO 数码管，`SW[14]=0` 显示 `12345678`，切为 1 显示递增的 `TICK_MS` 十六进制值。 |
| `diag_vga.mem` | LED `0202`。VGA 首格为白色 A，第二格为黄色 C。首行最末和第二行最左分别为红、绿方块，最右下为紫色 Z。 |
| `diag_key.mem` | LED `0203`。屏幕第 2 行打印原始十六进制字节，第 3 行相同位置打印逻辑键号。按下左键出现 `E0 6B` 和 `01`，松开出现 `E0 F0 6B`，逻辑键位置留空。 |
| `game.mem` | LED `600D` 表示初始化完成。方向键移动、旋转与软降，空格硬降，`P` 暂停或继续，`R` 重开，`ESC` 退出。VGA 显示棋盘、分数、行数、等级与状态。 |
| `game_demo.mem` | 同一游戏与驱动，固定生成 O 方块供演示。以出生位置为基准，依次左移 4 格、左移 2 格、原位、右移 2 格、右移 4 格，每次移好后按空格硬降。第五块落定后得 300 分、消 2 行。正式游戏镜像使用硬件 RNG。 |

所有入口上电都会检查 `SYS_ID`。LED `E001` 表示读值不符。游戏使用约 60 Hz 的逻辑帧，帧时长按 16、17、17 ms 循环。键盘驱动读状态后才取数据，持续按住控制键只触发一次，方向键每帧取最后一次。控制动作优先并按 FIFO 顺序保留到后续帧。检测到硬件溢出后清除前缀与按键队列，待硬件 FIFO 排空后重新解析。绘制只向显存写发生变化的字符对。

### 回归和行为仿真

沿用构建命令中的变量，先跑软件回归，再用 CPU RTL 加载镜像。`test_diag_mmio` 使用当前寄存器电路。其余四个测试的显存和 FIFO 由 `firmware_tb.sv` 模拟，CPU、执行和访存仍来自团队内核。

```powershell
$driver = Join-Path $repo 'software/tetris/stage2'
$driverLog = & $JavaExe '-Djava.awt.headless=true' -jar $RarsJar nc ae1 se2 sm 2000000 `
    "$driver/test_drivers.s" "$driver/ps2.s" "$driver/video.s"
$driverExit = $LASTEXITCODE
$driverLog
if ($driverExit -ne 0 -or 'PASS: all stage2 driver tests' -notin $driverLog) {
    throw 'RARS driver regression failed'
}

$root = Join-Path $repo 'riscv-cpu/riscv-cpu.srcs/sources_1/new'
$rtl = @(Get-ChildItem -LiteralPath "$root/RiscVCPU", "$root/peripherals" `
    -Recurse -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
Push-Location -LiteralPath $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv @rtl "$firmware/firmware_tb.sv"
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($test in 'test_diag_mmio','test_diag_vga','test_diag_key','test_game_firmware','test_game_demo') {
        & (Join-Path $VivadoBin 'xelab.bat') --mt off "work.$test" -s $test
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $test" }
        $log = & (Join-Path $VivadoBin 'xsim.bat') $test -runall
        $exitCode = $LASTEXITCODE
        $log
        if ($exitCode -ne 0 -or -not ($log -match '^PASS:') -or ($log -match '^Fatal:')) {
            throw "Simulation failed for $test"
        }
    }
} finally {
    Pop-Location
}
```

在同一仿真目录中执行 `xsim test_game_demo -runall -testplusarg capture_frames` 会保存 `demo-start.hex` 和 `demo-clear.hex`。每个转储是游戏对 VGA 模型写入的 80×30 个半字，格式见仓库 `INTERFACE.md`。

### 上板联调入口

组长接通 VGA 字符帧缓冲和 PS/2 FIFO 后，在 Vivado GUI 的游戏顶层选择 `MEM_FILE`，依次加载 `diag_mmio.mem`、`diag_vga.mem`、`diag_key.mem`、`game_demo.mem`、`game.mem`，分别综合、实现、生成 bitstream 和烧录。当前顶层的 CPU 默认约 50 Hz，游戏配置可以从 `CPU_CLOCK_INTERVAL=25`（按 100 MHz 输入推算为 2 MHz）起测，由组长结合实现时序确认。显存写入的译码应在寄存器和显存间互斥，`sw/sh` 字节使能及 `KEY_DATA` 的单次弹出时序需要在最终 RTL 上复验。

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
| `0x0100–0x013B` | 游戏状态和计时 |
| `0x0140–0x017F` | PS/2 解码状态和软件按键环形缓冲 |
| `0x0180–0x02FF` | 方块、计分、颜色和文字表 |
| `0x0300–0x03C7` | 上次绘制的 200 格棋盘 |
| `0x0400–0x04C7` | 合成后的 200 格待绘棋盘 |
| `0x04D0–0x04DF` | 分数、行数、等级和模式缓存 |
| `0x7000–0x7007` | 第 0 阶段 RAM 自检区 |
| `0x7800–0x7FFF` | 栈区，从初始 `sp=0x8000` 向低地址增长 |

第 0 阶段实际写入自检区和栈。游戏版启动代码应初始化实际使用的 RAM 区域，RARS 测试入口使用 RARS 自身的数据段和栈地址。

## 当前内核的指令旁路

当前 RTL 将 `LUI` 的立即数在写回阶段送入寄存器。EX 旁路取的是 ALU 结果，紧邻的依赖指令可能读到不同的值。第 0 阶段在这类 `LUI` 与使用者之间安排了两条独立指令，使使用者走 WB 旁路。汇编伪指令 `li` 可能展开为相邻的 `lui` 和 `addi`，后续生成 FPGA 镜像时应在已修复的内核上验证这类指令序列，或检查相关汇编的指令间距。
