`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// PipeliningTestbench —— 重定向流水线 RISC-V CPU 仿真测试平台
//
// 功能：
//   1. 载入 mem/BenchmarkCCAB.mem（课程 benchmark + CCAB 扩展指令测试程序）
//   2. 每个 CPU 周期向 Tcl 控制台输出一行关键状态：
//        [时间] 周期数 | PC / 指令字 / 助记符 | ID 段控制信号(ALUOP/ALUSrc/MemToReg/
//        MemWrite/RegWrite/译码信号) | EX 段(IR/重定向/分支/ecall) | MEM/WB 写信号 |
//        系统状态(运行/停机/load-use/中断使能/转发选择)
//   3. ecall 显示(a7==34)与 ecall 停机(a7!=34) 事件单独打标记行
//   4. 检测到停机后自动模拟“按下 Go 按键”继续（benchmark 中途有一次停机等待）
//   5. 运行 5000 个 CPU 周期后输出统计汇总（周期数/气泡数/load-use/分支数等）并 $finish
//
// 使用方式（Vivado GUI）：
//   1. 若 Sources 视图中本文件为灰色禁用，右键 → Enable File；
//   2. 右键 PipeliningTestbench → Set as Top（仿真顶层）；
//   3. Run Behavioral Simulation；输出显示在 Tcl Console 与 xsim.log。
//
// 注意：
//   - 仿真将 CPU_CLOCK_INTERVAL 置 1（cpu_clock = CLK/2 = 50MHz）以加速仿真；
//   - MEM_FILE 使用绝对路径（xsim 的 $readmemh 按工作目录解析相对路径）；
//     若工程移动位置，请修改下方 MEMFILE；或改用相对 xsim 工作目录的路径：
//     "../../../../srcs/sources_1/new/mem/BenchmarkCCAB.mem"
//   - 换程序仿真只需改 MEMFILE：InterruptTest.mem（中断测试）/ EcallTest.mem（ecall 冒烟）
//////////////////////////////////////////////////////////////////////////////////


module PipeliningTestbench;

    // ---------- 程序镜像路径 ----------
    localparam MEMFILE = "E:/experiments_and_reports/hardware_training/verilog/riscv-cpu/riscv-cpu.srcs/sources_1/new/mem/BenchmarkCCAB.mem";

    // ---------- 时钟与按键 ----------
    reg         CLK = 1'b0;
    reg         RST = 1'b1;
    reg         Go  = 1'b0;
    reg         IR1 = 1'b0, IR2 = 1'b0, IR3 = 1'b0;
    reg  [2:0]  DebugSel = 3'b000;
    reg  [15:0] SW = 16'b0;                // SW[15]=0 调试 LED；=1 MMIO LED 寄存器

    // ---------- DUT 输出 ----------
    wire        W1, W2, W3;
    wire [15:0] LED;
    wire [7:0]  SEG, AN;
    wire [31:0] PC, IR, RDin, MDin, LedData;
    wire        RegWrite, MemWrite;

    // ---------- tb 侧统计 ----------
    integer cpu_cycles = 0;              // tb 统计的 CPU 周期数（cpu_clock 上升沿计数）
    reg        go_req = 1'b0;           // Go 按键请求（初始启动 / 停机后继续共用）
    reg [7:0]  go_cnt = 8'b0;           // Go 按下保持计数器

    // ================= DUT：重定向流水线 CPU =================
    RedirectPipelineRiscV #(
        .CPU_CLOCK_INTERVAL(1),          // 仿真加速：cpu_clock = CLK/2 = 50MHz
        .DISPLAY_CLOCK_INTERVAL(1),
        .POR_CYCLES(200),                // 仿真里把上电复位缩短到 200 个 CLK（2us），板上默认为 50ms
        .MEM_FILE(MEMFILE)
    ) dut (
        .CLK(CLK), .RST(RST), .Go(Go),
        .IR1(IR1), .IR2(IR2), .IR3(IR3),
        .DebugSel(DebugSel), .SW(SW),
        .W1(W1), .W2(W2), .W3(W3), .LED(LED),
        .SEG(SEG), .AN(AN),
        .PC(PC), .IR(IR),
        .RDin(RDin), .MDin(MDin),
        .LedData(LedData), .RegWrite(RegWrite), .MemWrite(MemWrite)
    );

    // ================= 100MHz 板级时钟 =================
    always #5 CLK = ~CLK;

    // ================= 指令助记符译码（用于直观显示） =================
    function automatic string mnemonic(input [31:0] ir);
        logic [6:0] op = ir[6:0];
        logic [2:0] f3 = ir[14:12];
        logic [6:0] f7 = ir[31:25];
        begin
            case (op)
                7'b0110011: casez ({f7, f3})                 // R 型
                    10'b0000000_000: mnemonic = "ADD";
                    10'b0100000_000: mnemonic = "SUB";
                    10'b0000000_001: mnemonic = "SLL";
                    10'b0000000_010: mnemonic = "SLT";
                    10'b0000000_011: mnemonic = "SLTU";
                    10'b0000000_100: mnemonic = "XOR";
                    10'b0000000_101: mnemonic = "SRL";
                    10'b0100000_101: mnemonic = "SRA";
                    10'b0000000_110: mnemonic = "OR";
                    10'b0000000_111: mnemonic = "AND";
                    10'b0000001_000: mnemonic = "MUL";
                    10'b0000001_101: mnemonic = "DIVU";
                    10'b0000001_111: mnemonic = "REMU";
                    default: mnemonic = "R?";
                endcase
                7'b0010011: begin                               // I 型运算（funct7 位实为立即数，仅移位指令需区分）
                    case (f3)
                        3'b000: mnemonic = "ADDI";
                        3'b010: mnemonic = "SLTI";
                        3'b011: mnemonic = "SLTIU";
                        3'b100: mnemonic = "XORI";
                        3'b110: mnemonic = "ORI";
                        3'b111: mnemonic = "ANDI";
                        3'b001: mnemonic = "SLLI";
                        3'b101: mnemonic = (f7 == 7'b0100000) ? "SRAI" : "SRLI";
                        default: mnemonic = "I?";
                    endcase
                end
                7'b0000011: case (f3)                        // 取数
                    3'b000: mnemonic = "LB";
                    3'b001: mnemonic = "LH";
                    3'b010: mnemonic = "LW";
                    3'b100: mnemonic = "LBU";
                    3'b101: mnemonic = "LHU";
                    default: mnemonic = "L?";
                endcase
                7'b0100011: case (f3)                        // 存数
                    3'b000: mnemonic = "SB";
                    3'b001: mnemonic = "SH";
                    3'b010: mnemonic = "SW";
                    default: mnemonic = "S?";
                endcase
                7'b1100011: case (f3)                        // 条件分支
                    3'b000: mnemonic = "BEQ";
                    3'b001: mnemonic = "BNE";
                    3'b100: mnemonic = "BLT";
                    3'b101: mnemonic = "BGE";
                    3'b110: mnemonic = "BLTU";
                    3'b111: mnemonic = "BGEU";
                    default: mnemonic = "B?";
                endcase
                7'b1101111: mnemonic = "JAL";
                7'b1100111: mnemonic = "JALR";
                7'b0110111: mnemonic = "LUI";
                7'b0010111: mnemonic = "AUIPC";
                7'b1110011: case (f3)                        // 系统类
                    3'b000: mnemonic = ir[21] ? "URET" : "ECALL";
                    3'b110: mnemonic = "CSRRSI";
                    3'b111: mnemonic = "CSRRCI";
                    default: mnemonic = "SYS?";
                endcase
                default: mnemonic = "????";
            endcase
        end
    endfunction

    // ================= 复位 + 初次按下 Go 启动 =================
    initial begin
        RST = 1'b1;
        repeat (4) @(posedge CLK);
        RST = 1'b0;
        repeat (4) @(posedge CLK);
        go_req = 1'b1;      // 模拟按下 Go 开始运行
    end

    // ================= Go 按键脉冲生成（初始启动 / 停机后继续共用） =================
    always @(posedge CLK) begin
        if (go_req) begin
            Go <= 1'b1;
            go_cnt <= go_cnt + 8'd1;
            if (go_cnt == 8) begin
                go_cnt <= 8'b0;
                go_req <= 1'b0;
            end
        end else begin
            Go <= 1'b0;
        end
    end

    // ================= 停机检测：ecall(a7!=34) 停机后自动模拟按 Go 继续 =================
    reg halt_prev = 1'b0;
    always @(posedge CLK) begin
        if (dut.pipeline.halt_ff && !halt_prev) begin
            $display("        [TB] 检测到 CPU 停机（ecall halt），自动模拟按下 Go 继续执行");
            go_req <= 1'b1;
        end
        halt_prev <= dut.pipeline.halt_ff;
    end

    // ================= 每个 CPU 周期打印关键状态 =================
    // 格式：
    // [时间] C=周期 | PC IR 助记符 | ID:op as m2r mw rw 译码 | EX:ir rv bt ecD ecH
    //              | MEM:mw | WB:rw wd | run halt lu ie fwd1/fwd2
    always @(posedge dut.pipeline.cpu_clock) begin
        if (dut.pipeline.por_active) begin
            // 上电复位（POR）期间不打印、不计数
        end else begin
            cpu_cycles <= cpu_cycles + 1;
            #1;      // 等一拍，让本边沿的非阻塞更新与组合逻辑稳定后再采样
            $display("[%8t] C=%0d | PC=%08h IR=%08h %-6s | ID:op=%1h as=%b m2r=%b mw=%b rw=%b ct=%03x | EX:ir=%08h rv=%b bt=%b ecD=%b ecH=%b | MEM:mw=%b | WB:rw=%b wd=%08h | run=%b halt=%b lu=%b ie=%b fwd=%1d/%1d",
                 $time, cpu_cycles, PC, IR, mnemonic(IR),
                 dut.pipeline.id_alu_op,
                 dut.pipeline.id_alu_src,
                 dut.pipeline.id_mem_to_reg,
                 dut.pipeline.id_mem_write,
                 dut.pipeline.id_reg_write,
                 dut.pipeline.id_decode_ctrl,
                 dut.pipeline.idex_ir,
                 dut.pipeline.ex_redirect_valid,
                 dut.pipeline.ex_branch_taken,
                 dut.pipeline.ex_ecall_display,
                 dut.pipeline.ex_ecall_halt,
                 dut.pipeline.exmem_mem_write,
                 dut.pipeline.memwb_reg_write,
                 dut.pipeline.wb_data,
                 dut.pipeline.running_ff,
                 dut.pipeline.halt_ff,
                 dut.pipeline.load_use_stall,
                 dut.pipeline.ie_ff,
                 dut.pipeline.rs1_fwd,
                 dut.pipeline.rs2_fwd);
            if (dut.pipeline.ex_ecall_display)
                $display("        >> ecall 显示：a0=%08h 已锁存至 LedData", dut.pipeline.idex_rs2);
            if (dut.pipeline.ex_ecall_halt)
                $display("        >> ecall 停机：等待 Go 按键（tb 将自动模拟按键）");
            if (dut.pipeline.int_response)
                $display("        >> 中断响应：入口=%08h 断点EPC=%08h",
                         dut.pipeline.int_vector, dut.pipeline.idex_pc);
        end
    end

    // ================= 汇总与结束 =================
    initial begin
        $display("============================================================================");
        $display(" PipeliningTestbench：载入 BenchmarkCCAB.mem 开始仿真");
        $display(" 输出格式：[时间] C=周期 | PC/IR/助记符 | ID 控制信号 | EX | MEM | WB | 系统状态");
        $display("============================================================================");
        wait (RST === 1'b0);
        wait (dut.pipeline.por_active === 1'b0);   // 等上电复位(POR)释放后再统计
        repeat (5000) @(posedge dut.pipeline.cpu_clock);
        #1;
        $display("");
        $display("============================================================================");
        $display(" 仿真结束汇总");
        $display("   CPU 周期数 (tb 统计)       : %0d", cpu_cycles);
        $display("   总周期数 (CPU 内部计数器)  : %0d", dut.pipeline.total_cycles);
        $display("   插入气泡数                 : %0d", dut.pipeline.bubble_count);
        $display("   LoadUse 冲突次数           : %0d", dut.pipeline.loaduse_count);
        $display("   无条件分支数 (JAL/JALR)    : %0d", dut.pipeline.uncond_branch);
        $display("   条件分支成功数             : %0d", dut.pipeline.taken_branch);
        $display("   最终 PC / IR               : %08h / %08h", PC, IR);
        $display("   LedData 锁存值             : %08h", LedData);
        $display("   中断等待指示 W3/W2/W1      : %b/%b/%b", W3, W2, W1);
        $display("============================================================================");
        $finish;
    end

    // ================= 后续测试中断时可用的按键任务（示例） =================
    // 用法示例：initial 块中在某个时刻调用 press_ir1; 模拟按下 1 号中断按键
    // task automatic press_ir1;
    //     begin
    //         IR1 = 1'b1;
    //         repeat (4) @(posedge CLK);
    //         IR1 = 1'b0;
    //     end
    // endtask

endmodule
