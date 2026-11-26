# RISC-V 流水线 CPU · Nexys4 DDR 实验工程

> **HUST 硬件综合训练** 课程项目（2026 秋季学期）
> 基于 Verilog 的 32 位 RISC-V 处理器实现，支持 **单周期 / 理想流水线 / 气泡流水线 / 重定向流水线 + 单级中断** 四种变体，并配套指令测试程序与仿真测试台。

---

## 1. 项目概述

| 项目 | 内容 |
|---|---|
| 目标板卡 | Digilent **Nexys4 DDR**（XC7A100T-CSG324，100 MHz 主时钟） |
| 开发环境 | **Vivado 2022.1**（工程文件 `riscv-cpu/riscv-cpu.xpr`） |
| 处理器 | 32 位 RISC-V，**5 级流水线**（IF/ID/EX/MEM/WB），哈佛结构 |
| 存储 | 指令 ROM 1024 字、数据 RAM 1024 字，均由 `$readmemh` 从 `.mem` 文件装载 |
| 调试接口 | 8 位数码管、16 个 LED、5 个按键、16 位拨码开关 |
| 目录说明 | `riscv-cpu/` 为 Vivado 工程；`Reference/` 为课程参考仓库；`Schematics/` 及两个 PDF 为板卡资料 |

## 2. 工程结构（RTL 源文件）

游戏软件入口见 [software/tetris/README.md](software/tetris/README.md)。

```
software/tetris/
├── README.md                     # 软件构建、RAM 布局与仿真步骤
├── stage0/                       # RARS 与 FPGA 启动自检、ROM 导出和仿真测试台
├── stage1/                       # 游戏核心、RARS 终端原型和固定输入回归
├── stage2/                       # MMIO、PS/2、字符显存驱动和独立自检入口
└── stage3/                       # 游戏固件、构建入口和 CPU RTL 联调测试台
```

```
riscv-cpu/riscv-cpu.srcs/
├── constrs_1/new/Nexys4_DDR_Master.xdc        # 引脚与时钟约束
├── sim_1/new/PipeliningTestbench.sv           # 仿真测试台（打印逐周期流水状态）
└── sources_1/new/
    ├── mem/                                   # 测试程序（.mem）
    │   ├── InterruptTest_fixed.mem            # ★当前顶层使用：补丁版单级中断测试
    │   ├── InterruptTest.mem                  # 课程原版中断测试（hex 转换）
    │   ├── BenchmarkCCAB.mem                  # CCAB 基准测试（24 指令 + 扩展）
    │   ├── EcallTest.mem                      # ecall 显示/停机测试
    │   └── SimpleSingleCycleRiscV.mem         # 单周期冒烟测试
    ├── RiscVCPU/                              # CPU 内核（顶层 + 各部件分类）
    │   ├── Nexys4DDRTop.v                     # ★顶层模块
    │   ├── stages/                            # 五级流水段：IF/ID/EX/MEM/WB
    │   ├── pipe_regs/                         # 流水线级间寄存器（IF2ID/ID2EX/EX2MEM/MEM2WB）
    │   ├── alu/                               # ALU 与运算码生成（ALU/OPGenerate）
    │   ├── control/                           # 控制器（ControlSignGenerate/HardwaredController）
    │   ├── regfile/                           # 寄存器堆与读端口检测（RegFile/RegUse）
    │   ├── forwarding/                        # 转发与 LoadUse 检测（DataWatch）
    │   ├── io/                                # 分频器与数码管显示（Divider/LedDisplay）
    │   └── cores/                             # 四个 CPU 变体封装
    └── peripherals/                           # 外设电路（非 CPU 架构部分）
        └── mmio/
            └── MMIO.v                         # MMIO 外设寄存器组（SYS_ID/按键/LED/数码管/TICK_MS/CYCLES/RNG/KEY_*）
```

## 3. 电路中的几个 CPU

四个变体共享同一套部件模块（stages/alu/control 等），区别在于流水线控制方式与中断支持：

| CPU 封装 | 文件 | 特点 |
|---|---|---|---|
| `SimpleSingleCycleRiscV` | `cores/SimpleSingleCycleRiscV.v` | 单周期、无流水 |
| `IdealPipelineRiscV` | `cores/IdealPipelineRiscV.v` | 理想流水线（不处理冒险） | 
| `BubblePipelineingRiscV` | `cores/BubblePipelineingRiscV.v` | 气泡式处理数据冒险 | 
| `RedirectPipelineRiscV` | `cores/RedirectPipelinengRiscV.v` | **重定向处理控制冒险 + 单级中断**（当前顶层使用） | 

前三个流水变体复用同一个内核 `PipelineRiscVCore`（定义在 `cores/IdealPipelineRiscV.v` 中，参数 `ENABLE_REDIRECT` 区分气泡/重定向模式）。

## 4. 最先进 CPU：重定向流水线 + 单级中断

### 4.1 流水线特性

- **5 级流水**：取指（IF）→ 译码（ID）→ 执行（EX）→ 访存（MEM）→ 写回（WB），指令/数据存储器异步读；
- **分支重定向**：BEQ/BNE/BLT/BGE/BLTU/BGEU、JAL、JALR 均在 EX 段解析，命中后冲刷 IF/ID 段并跳转；
- **3 级数据转发**：EX/MEM/WB 结果旁路（近者优先），可消除绝大多数数据冒险；
- **LoadUse 气泡**：load 后一条指令使用其结果的场景自动插入一个气泡（计数器统计）；
- **x0 恒为 0**：寄存器堆硬连线实现；
- **性能计数器**：总周期数、插入气泡数、LoadUse 次数、无条件分支数、条件分支成功数（可由拨码开关选通到数码管显示）。

### 4.2 单级中断

- **三个中断源**：IR1 < IR2 < IR3，**优先级 1 最低、3 最高**；
- **中断向量**：`0x000000AC`（IR1）、`0x000001AC`（IR2）、`0x000002BC`（IR3），对应补丁版测试程序 `InterruptTest_fixed.mem`；
- **挂起机制**：按键请求锁存进 `pending` 寄存器，服务完成后自动清除（对应 LED 的 W1/W2/W3 指示）；
- **响应条件**：中断使能 IE=1 且流水线不在气泡中；**复位后 IE 默认为 1**（中断默认使能，测试程序无需显式开中断）；
- **响应动作**：硬件自动关中断（IE←0）、保存断点 EPC←被中断指令的 PC、冲刷流水线、跳转中断入口；
- **返回**：ISR 末尾执行 `URET`（`0x00200073`）：EPC→PC、开中断（IE←1）、清除已服务的挂起标志；
- **ISR 期间新请求**：只挂起不响应，当前 ISR 返回后按优先级依次响应（符合任务书要求）。

### 4.3 ecall 系统调用约定

| a7 值 | 行为 |
|---|---|
| `34` | 将 a0 的值锁存到数码管显示（LedData），**不阻塞流水线** |
| 其它 | **停机等待 Go 按键**（课程约定，用于程序暂停/结束） |

## 5. CPU 参数与接口

### 5.1 参数（四个封装模块通用）

| 参数 | 默认值 | 说明 |
|---|---|---|
| `CPU_CLOCK_INTERVAL` | `1_000_000` | CPU 时钟分频：f_cpu = 100MHz / (2×N) = **50 Hz**（游戏/演示可调小提速） |
| `DISPLAY_CLOCK_INTERVAL` | `50_000` | 数码管扫描 1 kHz，8 位整轮刷新 125 Hz |
| `POR_CYCLES` | `5_000_000` | 上电自动复位时长 = 5M 个 CLK ≈ **50 ms** |
| `ENABLE_REDIRECT` | `1` | 重定向使能（内核参数，气泡变体置 0） |
| `INT_ADDR_1/2/3` | `0xAC / 0x1AC / 0x2BC` | 三个中断入口地址（与当前测试程序对应） |
| `MEM_FILE` | `../../mem/…` | 指令 ROM 初始化文件（相对 `stages/IF.v` 所在目录解析） |

### 5.2 顶层接口（`Nexys4DDRTop`）

| 端口 | 方向 | 板载资源 | 引脚 | 功能 |
|---|---|---|---|---|
| `CLK` | in | 系统时钟 | E3 | 100 MHz |
| `RST` | in | BTNU（上键） | M18 | 复位；**复位后自动开始运行** |
| `Go` | in | BTNC（中键） | N17 | ecall 停机后继续运行 |
| `IR1` | in | BTNL（左键） | P17 | 1 号中断请求 |
| `IR2` | in | BTNR（右键） | M17 | 2 号中断请求 |
| `IR3` | in | BTND（下键） | P18 | 3 号中断请求 |
| `SW[15:0]` | in | 拨码开关 | — | `SW[2:0]` 为数码管调试显示选择（见 6.3） |
| `SEG[7:0]` | out | 数码管段选 | — | 7 段 + 小数点 |
| `AN[7:0]` | out | 数码管位选 | — | 8 位扫描 |
| `LED[15:0]` | out | 16 个 LED | — | `LED[15]=W3`、`LED[14]=W2`、`LED[13]=W1`（中断等待指示）、`LED[12:0]=PC[12:0]` |

> 输入引脚均在 XDC 中设置了 **PULLDOWN**（内部下拉），避免悬空误触发（也兼容板载下拉电阻虚焊的情况）。

## 6. 支持的指令集

### 6.1 RV32I 基础指令集（除注明外全部实现）

| 类别 | 指令 |
|---|---|
| 算术立即数 | ADDI、SLTI、SLTIU、XORI、ORI、ANDI、SLLI、SRLI、SRAI |
| 寄存器运算 | ADD、SUB、SLL、SLT、SLTU、XOR、SRL、SRA、OR、AND |
| 条件分支 | BEQ、BNE、BLT、BGE、BLTU、BGEU |
| 跳转 | JAL、JALR（JALR 自动清最低位、写回 PC+4） |
| 访存 | LB、LH、LW、LBU、LHU、SB、SH、SW（字节/半字读改写，五种立即数格式齐全） |
| 高位立即数 | LUI、AUIPC |
| 系统 | ECALL（课程语义见 4.3）；FENCE 按 NOP 处理；EBREAK 未区分（按 ECALL 停机） |

### 6.2 课程自定义扩展（超出 RV32I）

| 指令 | 编码 | 说明 |
|---|---|---|
| `MUL` / `DIVU` / `REMU` | funct7=`0000001` | M 扩展子集（REMU 余数走 Result2 写回；除 0 返回 0） |
| `URET` | `0x00200073` | 单级中断返回（EPC→PC + 开中断 + 清标志） |
| `CSRRSI` / `CSRRCI` | funct3=`110`/`111` | 简化为**开中断 IE←1 / 关中断 IE←0** |

## 7. 测试程序与操作说明

当前顶层装载 **`mem/InterruptTest_fixed.mem`**（补丁版单级中断测试程序：主程序为走马灯，三个 ISR 分别为 SRLV 移位 / SB 访存 / BLT 分支测试，ISR 现场保护已补全）。

### 7.1 上电流程

1. 烧录 bitstream（`riscv-cpu.runs/impl_1/Nexys4DDRTop.bit`）；
2. 上电后 POR 自动复位约 50 ms，随后 **CPU 自动开始运行**（无需按任何键），数码管显示走马灯滚动图案。

### 7.2 按键功能

| 按键 | 功能 |
|---|---|
| **BTNL（IR1）** | 触发 1 号中断 → 数码管依次显示 SRLV 移位序列 `87600000→08760000→…→00000000` |
| **BTNR（IR2）** | 触发 2 号中断 → 依次显示 `00,01,…,1F`（逐字节写入），再读回显示 `03020100,07060504,…,1F1E1D1C` |
| **BTND（IR3）** | 触发 3 号中断 → 显示 `FFFFFFF1→…→FFFFFFFF`，再显示 `1,3,6,A,F,15,1C,24` |
| **BTNC（Go）** | 每个 ISR 显示结束执行 `a7=10 的 ecall` 会**停机**，按 Go 继续执行"恢复现场 → URET → 返回主程序" |
| **BTNU（RST）** | 复位，复位后自动重新开始运行 |

**中断优先级 1 < 2 < 3**：同时或 ISR 执行期间按多个键时，先响应 3 号、再 2 号、最后 1 号；ISR 期间新按的键对应 W 灯点亮（挂起），当前 ISR 返回后再响应。

### 7.3 LED 与拨码开关

| 资源 | 功能 |
|---|---|
| `LED[13] = W1`、`LED[14] = W2`、`LED[15] = W3` | 中断等待指示：亮 = 有未服务的中断请求 |
| `LED[12:0]` | 当前 PC 的低 13 位 |
| `SW[2:0]` | 数码管调试显示选择（下表） |

> **LED 显示源选择（SW[15]）**：`SW[15]=0`（默认）→ 上面的调试显示（W1-3 + PC），课程验收保持原样；`SW[15]=1` → **MMIO LED 寄存器**（`0xFFFF_0008`，游戏软件控制 16 个 LED 用）。

| SW[2:0] | 数码管显示内容 |
|---|---|
| `000` | ecall 锁存显示值 LedData（默认，看程序输出用这个） |
| `001` | 总周期数 |
| `010` | 插入气泡数 |
| `011` | PC |
| `100` | LoadUse 冲突次数 |
| `101` | 无条件分支数（JAL/JALR） |
| `110` | 条件分支成功数 |
| `111` | **MMIO SEG7 寄存器**（`0xFFFF_000C`，游戏里显示分数/等级用） |

### 7.4 更换测试程序

修改 `RiscVCPU/Nexys4DDRTop.v` 中 `cpu` 实例的 `.MEM_FILE(...)`，然后重新综合实现：

- 跑 `BenchmarkCCAB.mem`：改 `../../mem/BenchmarkCCAB.mem`（注意 CCAB 基准用不到中断）；
- 跑课程原版 `InterruptTest.mem`：需同时把 `INT_ADDR_2/3` 改回 `0x150/0x1F4`；
- 跑 `InterruptTest_fixed.mem`：保持当前参数（入口 `0xAC/0x1AC/0x2BC`）不变。

### 7.5 仿真

- 测试台：`sim_1/new/PipeliningTestbench.sv`，逐周期打印 PC/IR/各段控制信号/中断事件，并自动模拟 Go 按键；
- 可在 Vivado 中直接运行行为仿真，或使用 xvlog/xelab/xsim 命令行流程（源文件按 `RiscVCPU/` 目录树递归编译）。

## 8. 给 AI 助手的说明

🤖 使用 AI 助手（DeepSeek、ChatGPT、Codex、Cursor、Claude Code 等）协助本工程时，请先让助手阅读并遵守 **[`AGENTS.md`](./AGENTS.md)**（规范包括：新对话开始的必读清单、临时文件不得污染工程目录、不自行运行 Vivado 综合/实现流程、对话开始的行为提醒、规范变更的即时同步等）。

外设接入相关的接口约定（MMIO 地址表、显存格式、键盘队列、IO 缓冲区）统一见 **[`INTERFACE.md`](./INTERFACE.md)**，硬件组与软件组都以其为唯一接口依据。
