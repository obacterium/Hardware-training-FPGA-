`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// PipelineRiscVCore：五段流水线 RISC-V CPU 内核（理想/气泡/重定向共用）
//
// 相对原框架的修正与补齐（对照任务书与 cpu21-riscv_flow.circ 的◇重定向流水线）：
//   1. ecall 正确语义：a7==34 → LedData 锁存显示 a0；a7!=34 → 停机，等待 Go(BTNC) 按下继续
//   2. Go 按键：按下即启动/继续（运行控制 FF），复位后等待 Go 开始执行
//   3. 统一复位 RST（任务书注意事项15）
//   4. 数据转发修正：EX/MEM/WB 三级转发（近者优先），MEM 级取数也可转发（RAM 异步读）
//   5. 单级中断：IR1/IR2/IR3 三个按键源（优先级 1<2<3）、IE/EPC、中断隐指令、URET/CSRRSI/CSRRCI
//   6. 统计计数器：总周期数/插入气泡数/LoadUse次数/无条件分支数/条件分支成功数
//   7. 全指令集译码（24 条基本指令 + CCAB 全集）在 ControlSignGenerate/ALU_OPGenerate 中完成
//////////////////////////////////////////////////////////////////////////////////


module PipelineRiscVCore #(
    parameter integer CPU_CLOCK_INTERVAL     = 1_000_000,
    parameter integer DISPLAY_CLOCK_INTERVAL = 50_000,   // 数码管扫描 100MHz/(2*50000)=1kHz，整轮刷新 125Hz
    parameter integer POR_CYCLES             = 5_000_000,// 上电自动复位时长（CLK 周期数，100MHz 下 5M=50ms）
    parameter integer ENABLE_REDIRECT        = 1,
    parameter [31:0] INT_ADDR_1 = 32'h000000AC,   // 1 号中断入口（对应 InterruptTest_fixed.mem 补丁版中断测试程序）
    parameter [31:0] INT_ADDR_2 = 32'h000001AC,   // 2 号中断入口
    parameter [31:0] INT_ADDR_3 = 32'h000002BC,   // 3 号中断入口
    parameter MEM_FILE = "../../mem/SimpleSingleCycleRiscV.mem"
    )(
    input         CLK,
    input         RST,
    input         Go,
    input         IR1,
    input         IR2,
    input         IR3,
    input  [2:0]  DebugSel,
    input  [15:0] SW,             // 拨码开关（SW_BTN 寄存器 + LED 显示源选择 SW[15]）
    output        W1,
    output        W2,
    output        W3,
    output [15:0] LED,            // SW[15]=0 调试显示(W1-3+PC) / SW[15]=1 MMIO LED 寄存器
    output [7:0]  SEG,
    output [7:0]  AN,
    output [31:0] PC,
    output [31:0] IR,
    output [31:0] RDin,
    output [31:0] MDin,
    output [31:0] LedData,
    output        RegWrite,
    output        MemWrite
    );

    wire cpu_clock;
    wire [31:0] if_pc, if_ir;
    wire [31:0] id_rs1, id_rs2, id_imm_i, id_imm_b, id_imm_j;
    wire [4:0] id_rs1_id, id_rs2_id;
    wire id_rs1_used, id_rs2_used;
    wire [3:0] id_alu_op;
    wire id_alu_src, id_mem_to_reg, id_mem_write, id_reg_write;
    wire id_beq, id_bne, id_blt, id_jalr, id_jal, id_utype, id_stype, id_dasb;
    wire [4:0] id_write_reg;
    wire [9:0] id_decode_ctrl;
    wire [31:0] ifid_ir, ifid_pc;
    wire [31:0] idex_pc, idex_rs1, idex_rs2, idex_imm_i, idex_imm_b, idex_imm_j, idex_ir;
    wire [4:0] idex_write_reg;
    wire [3:0] idex_alu_op;
    wire [9:0] idex_decode_ctrl;
    wire idex_alu_src, idex_mem_to_reg, idex_mem_write, idex_reg_write;
    wire [31:0] ex_alu_result, ex_result2, ex_store_data, ex_redirect_pc;
    wire ex_equal, ex_branch_taken, ex_redirect_valid;
    wire ex_ecall_display, ex_ecall_halt;
    wire [31:0] exmem_pc, exmem_alu_result, exmem_write_data, exmem_ir;
    wire [31:0] exmem_reserved1, exmem_reserved2, mem_read_data;
    wire [4:0] exmem_write_reg;
    wire [9:0] exmem_decode_ctrl;
    wire exmem_mem_to_reg, exmem_reg_write, exmem_mem_write;
    wire [31:0] memwb_pc, memwb_alu_result, memwb_mem_data, memwb_ir;
    wire [31:0] memwb_reserved1, memwb_reserved2, wb_data;
    wire [4:0] memwb_write_reg, wb_reg;
    wire [9:0] memwb_decode_ctrl;
    wire memwb_mem_to_reg, memwb_reg_write, wb_reg_write;
    wire load_use_stall;
    wire [1:0] rs1_fwd, rs2_fwd;
    wire data_correlate;
    wire [31:0] forwarded_rs1, forwarded_rs2;
    wire [9:0] ex_control = idex_decode_ctrl;
    wire [31:0] mmio_read_data;      // MMIO 外设读数据
    wire [15:0] mmio_led;            // MMIO LED 寄存器
    wire [31:0] mmio_seg7;           // MMIO SEG7 寄存器
    reg [15:0] total_cycles, bubble_count, loaduse_count, uncond_branch, taken_branch;   // 统计计数器（提前声明供 MMIO 引用）

    assign id_decode_ctrl = {id_jalr, id_jal, id_beq, id_bne, id_blt,
                             1'b0, 1'b0, id_stype, id_utype, id_dasb};

    // ================= 复位（上电自动复位 POR + 按键复位 RST，同步到 CLK 域） =================
    // POR：配置完成后自动复位 POR_CYCLES 个 CLK（默认 50ms），随后释放并自动运行——
    // 即使不按任何按键也能启动；板上按键下拉电阻虚焊导致 RST 浮空时由 XDC 内部 PULLDOWN 兜底。
    reg [31:0] por_cnt = 32'b0;   // 初始化防止仿真 X 态（硬件 FF 上电亦为 0）
    wire por_active = (por_cnt < POR_CYCLES);
    always @(posedge CLK) begin
        if (por_active) por_cnt <= por_cnt + 32'd1;
    end
    reg rst_s1, rst_s2;
    always @(posedge CLK) begin rst_s1 <= por_active | RST; rst_s2 <= rst_s1; end
    wire rst_synced = rst_s2;

    // ================= 按键同步（Go / 中断源，两拍同步） =================
    reg go_s1, go_s2, ir1_s1, ir1_s2, ir2_s1, ir2_s2, ir3_s1, ir3_s2;
    always @(posedge CLK) begin
        go_s1 <= Go;  go_s2 <= go_s1;
        ir1_s1 <= IR1; ir1_s2 <= ir1_s1;
        ir2_s1 <= IR2; ir2_s2 <= ir2_s1;
        ir3_s1 <= IR3; ir3_s2 <= ir3_s1;
    end

    // ================= 运行控制：复位后自动运行；ecall 停机→halt；Go 按下→继续 =================
    reg running_ff, halt_ff;
    always @(posedge cpu_clock) begin
        if (rst_synced) begin
            running_ff <= 1'b1;   // 复位后自动开始运行（Go 仍用于 ecall 停机后的继续）
            halt_ff    <= 1'b0;
        end else begin
            if (go_s2) begin
                running_ff <= 1'b1;
                halt_ff    <= 1'b0;
            end else if (ex_ecall_halt) begin
                halt_ff <= 1'b1;
            end
        end
    end

    // ================= 单级中断控制器（IE/EPC/pending/优先级 1<2<3） =================
    // IE 复位后默认为 1（中断默认使能）：课程“单级中断测试程序”不执行 csrrsi 开中断，
    // 参考框架的“单周期+单级中断”电路亦无 IE 寄存器（响应时硬件自动关、uret 自动开）。
    // csrrsi/csrrci 仍可在 EX 段动态开关中断。
    reg        ie_ff = 1'b1;
    reg [31:0] epc_ff;
    reg [1:0]  served_ff;
    reg [2:0]  pending;          // pending[0]=IR1, [1]=IR2, [2]=IR3
    reg ir1_d, ir2_d, ir3_d;

    always @(posedge cpu_clock) begin
        ir1_d <= ir1_s2; ir2_d <= ir2_s2; ir3_d <= ir3_s2;
    end
    wire ir1_press = ir1_s2 & ~ir1_d;
    wire ir2_press = ir2_s2 & ~ir2_d;
    wire ir3_press = ir3_s2 & ~ir3_d;

    wire ex_uret   = (idex_ir[6:2] == 5'b11100) && (idex_ir[14:12] == 3'b000) &&  idex_ir[21];
    wire ex_ecall  = (idex_ir[6:2] == 5'b11100) && (idex_ir[14:12] == 3'b000) && ~idex_ir[21];
    wire ex_csrrsi = (idex_ir[6:2] == 5'b11100) && (idex_ir[14:12] == 3'b110);
    wire ex_csrci  = (idex_ir[6:2] == 5'b11100) && (idex_ir[14:12] == 3'b111);

    // ---- 中断仲裁与流水控制（声明于 always 之前） ----
    wire [1:0] priority_id = pending[2] ? 2'd3 :
                             pending[1] ? 2'd2 : 2'd1;
    wire int_req = ie_ff & (|pending) & running_ff & ~halt_ff;
    wire ex_bubble = (idex_ir == 32'h00000000);   // 气泡中不响应中断
    wire int_response = int_req & ~ex_bubble;
    wire [31:0] int_vector = (priority_id == 2'd3) ? INT_ADDR_3 :
                             (priority_id == 2'd2) ? INT_ADDR_2 : INT_ADDR_1;
    // 分支重定向为正确性所必需（气泡/重定向变体均需），ENABLE_REDIRECT 保留为兼容参数
    wire redirect_control_valid = ex_redirect_valid;
    wire ex_en = running_ff & ~halt_ff;
    wire if_en = running_ff & ~halt_ff & (~load_use_stall | int_response);
    wire redirect_valid_final = int_response | redirect_control_valid;
    wire [31:0] redirect_pc_final = int_response ? int_vector : ex_redirect_pc;

    always @(posedge cpu_clock) begin
        if (rst_synced) begin
            ie_ff     <= 1'b1;   // 复位后中断默认使能（课程测试程序不显式开中断）
            epc_ff    <= 32'b0;
            served_ff <= 2'b00;
            pending   <= 3'b000;
        end else begin
            // 按键边沿 → 锁存中断请求（ISR 结束前不重复触发）
            if (ir1_press) pending[0] <= 1'b1;
            if (ir2_press) pending[1] <= 1'b1;
            if (ir3_press) pending[2] <= 1'b1;
            // 中断响应 / 中断返回 / 开关中断
            if (int_response) begin
                ie_ff     <= 1'b0;          // 硬件关中断
                epc_ff    <= idex_pc;       // 保存断点（EX 段指令的 PC）
                served_ff <= priority_id;   // 记录被服务的中断源
            end else if (ex_uret && ex_en) begin
                ie_ff     <= 1'b1;          // 开中断
                served_ff <= 2'b00;
                case (served_ff)            // 清除被服务中断源的中断请求
                    2'd1: pending[0] <= 1'b0;
                    2'd2: pending[1] <= 1'b0;
                    2'd3: pending[2] <= 1'b0;
                    default: ;
                endcase
            end else if (ex_csrrsi && ex_en) begin
                ie_ff <= 1'b1;              // CSRRSI 简化为开中断
            end else if (ex_csrci && ex_en) begin
                ie_ff <= 1'b0;              // CSRRCI 简化为关中断
            end
        end
    end

    assign W1 = pending[0];
    assign W2 = pending[1];
    assign W3 = pending[2];
    // LED 显示源选择：SW[15]=0 → 调试（W1-3 + PC 低13位，课程验收默认）；SW[15]=1 → MMIO LED 寄存器
    assign LED = SW[15] ? mmio_led : {W3, W2, W1, if_pc[12:0]};

    // ================= 流水控制 =================
    // （redirect_control_valid / ex_en / if_en / redirect_* 等信号已在上方中断控制器之前声明）

    // ================= 数据转发（EX/MEM/WB 三级，近者优先） =================
    DataWatch data_watch (
        .rs1_id(id_rs1_id), .rs2_id(id_rs2_id),
        .rs1_used_in(id_rs1_used), .rs2_used_in(id_rs2_used),
        .ex_reg_write(idex_reg_write), .mem_reg_write(exmem_reg_write),
        .wb_reg_write(memwb_reg_write),
        .ex_mem_to_reg(idex_mem_to_reg), .ex_rd(idex_write_reg),
        .mem_rd(exmem_write_reg), .wb_rd(memwb_write_reg),
        .rs1Fwd(rs1_fwd), .DataCorrelate(data_correlate), .rs2Fwd(rs2_fwd),
        .LoadUse(load_use_stall)
    );
    wire [31:0] mem_result = exmem_mem_to_reg ? mem_read_data : exmem_alu_result;
    assign forwarded_rs1 = rs1_fwd == 2'b01 ? ex_alu_result :
                           rs1_fwd == 2'b10 ? mem_result :
                           rs1_fwd == 2'b11 ? wb_data : id_rs1;
    assign forwarded_rs2 = rs2_fwd == 2'b01 ? ex_alu_result :
                           rs2_fwd == 2'b10 ? mem_result :
                           rs2_fwd == 2'b11 ? wb_data : id_rs2;

    assign PC = if_pc;
    assign IR = if_ir;
    assign RDin = wb_data;
    assign MDin = exmem_write_data;
    assign RegWrite = memwb_reg_write;
    assign MemWrite = exmem_mem_write;

    // ================= 取指 =================
    IF #(.CLOCK_INTERVAL(CPU_CLOCK_INTERVAL), .MEM_FILE(MEM_FILE)) instruction_fetch (
        .CLK(CLK), .RST(rst_synced), .Go(if_en),
        .redirect_valid(redirect_valid_final), .redirect_pc(redirect_pc_final),
        .cpu_clock(cpu_clock), .PC(if_pc), .IR(if_ir)
    );

    // ================= 译码 =================
    ID instruction_decode (
        .cpu_clock(cpu_clock), .RST(rst_synced), .PC(ifid_pc), .IR(ifid_ir),
        .wb_enable(wb_reg_write & ex_en), .wb_address(wb_reg), .wb_data(wb_data),
        .RS1(id_rs1), .RS2(id_rs2), .ImmI(id_imm_i), .ImmB(id_imm_b), .ImmJ(id_imm_j),
        .ALU_OP(id_alu_op), .ALU_SRC(id_alu_src), .MemToReg(id_mem_to_reg),
        .MemWrite(id_mem_write), .RegWrite(id_reg_write), .Beq(id_beq), .Bne(id_bne),
        .Blt(id_blt), .JALR(id_jalr), .JAL(id_jal), .Utype(id_utype), .Stype(id_stype),
        .DASB(id_dasb), .WriteReg(id_write_reg), .rs1_id(id_rs1_id),
        .rs2_id(id_rs2_id), .rs1_used(id_rs1_used), .rs2_used(id_rs2_used)
    );

    // ================= 执行 =================
    EX execute (
        .PC(idex_pc), .RS1(idex_rs1), .RS2(idex_rs2), .ImmI(idex_imm_i),
        .ImmB(idex_imm_b), .ImmJ(idex_imm_j), .IR(idex_ir), .EPC(epc_ff),
        .ALU_OP(idex_alu_op), .ALU_SRC(idex_alu_src),
        .ALUResult(ex_alu_result), .Result2(ex_result2),
        .StoreData(ex_store_data), .Equal(ex_equal),
        .BranchTaken(ex_branch_taken), .RedirectValid(ex_redirect_valid),
        .RedirectPC(ex_redirect_pc), .EcallDisplay(ex_ecall_display),
        .EcallHalt(ex_ecall_halt)
    );

    // ================= 访存 =================
    MEM memory_access (
        .cpu_clock(cpu_clock), .Go(ex_en), .MemWrite(exmem_mem_write),
        .IR(exmem_ir), .Address(exmem_alu_result),
        .WriteData(exmem_write_data), .MMIO_ReadData(mmio_read_data),
        .ReadData(mem_read_data)
    );

    // ================= MMIO 外设寄存器组（Stage 1，INTERFACE.md §3） =================
    MMIO mmio_periph (
        .CLK(CLK), .cpu_clock(cpu_clock), .RST(rst_synced),
        .Go(ex_en), .MemWrite(exmem_mem_write),
        .Address(exmem_alu_result), .WriteData(exmem_write_data),
        .SW(SW), .BTNU(RST), .BTND(IR3), .BTNL(IR1), .BTNR(IR2), .BTNC(go_s2),
        .Cycles(total_cycles),
        .ReadData(mmio_read_data), .LED(mmio_led), .SEG7Reg(mmio_seg7)
    );

    // ================= 写回 =================
    WB writeback (
        .PC(memwb_pc), .IR(memwb_ir),
        .ALUResult(memwb_alu_result), .Result2(memwb_reserved1),
        .MemData(memwb_mem_data), .MemToReg(memwb_mem_to_reg),
        .RegWriteIn(memwb_reg_write), .WriteData(wb_data),
        .RegWrite(wb_reg_write), .WriteReg(wb_reg)
    );

    // ================= 流水接口 =================
    PipelinengIF2ID if_id (
        .clk(cpu_clock), .RST(rst_synced), .en_n(~if_en),
        .bubble(redirect_valid_final),
        .predict_jump_in(1'b0), .ir_in(if_ir), .pc_in(if_pc),
        .predict_jump_out(), .ir_out(ifid_ir), .ir_debug_out(), .pc_out(ifid_pc)
    );

    PipelinengID2EX id_ex (
        .clk(cpu_clock), .RST(rst_synced), .en_n(~ex_en),
        .bubble(load_use_stall | redirect_control_valid | int_response),
        .pc_in(ifid_pc), .rs1_in(forwarded_rs1), .rs2_in(forwarded_rs2), .imm32_in(id_imm_i),
        .imm_b_in(id_imm_b), .imm_j_in(id_imm_j), .ir_in(ifid_ir),
        .write_reg_in(id_write_reg), .alu_op_in(id_alu_op), .decode_ctrl_in(id_decode_ctrl),
        .alu_src_in(id_alu_src), .mem_to_reg_in(id_mem_to_reg), .mem_write_in(id_mem_write),
        .reg_write_in(id_reg_write), .rs1_fwd_in(2'b0), .rs2_fwd_in(2'b0),
        .predict_jump_in(1'b0), .pc_out(idex_pc), .rs1_out(idex_rs1), .rs2_out(idex_rs2),
        .imm32_out(idex_imm_i), .imm_b_out(idex_imm_b), .imm_j_out(idex_imm_j),
        .ir_out(idex_ir), .write_reg_out(idex_write_reg), .alu_op_out(idex_alu_op),
        .decode_ctrl_out(idex_decode_ctrl), .alu_src_out(idex_alu_src),
        .mem_to_reg_out(idex_mem_to_reg), .mem_write_out(idex_mem_write),
        .reg_write_out(idex_reg_write), .rs1_fwd_out(), .rs2_fwd_out(), .predict_jump_out()
    );

    PipelinengEX2MEM ex_mem (
        .clk(cpu_clock), .RST(rst_synced), .en_n(~ex_en),
        .bubble(int_response), .halt_in(1'b0),
        .pc_in(idex_pc), .alu_result_in(ex_alu_result), .write_data_in(ex_store_data),
        .ir_in(idex_ir), .reserved1_in(ex_result2), .reserved2_in(32'b0),
        .write_reg_in(idex_write_reg), .decode_ctrl_in(idex_decode_ctrl),
        .mem_to_reg_in(idex_mem_to_reg), .reg_write_in(idex_reg_write), .mem_write_in(idex_mem_write),
        .halt_out(), .pc_out(exmem_pc), .alu_result_out(exmem_alu_result),
        .write_data_out(exmem_write_data), .ir_out(exmem_ir), .reserved1_out(exmem_reserved1),
        .reserved2_out(exmem_reserved2), .write_reg_out(exmem_write_reg),
        .decode_ctrl_out(exmem_decode_ctrl), .mem_to_reg_out(exmem_mem_to_reg),
        .reg_write_out(exmem_reg_write), .mem_write_out(exmem_mem_write)
    );

    PipelinengMEM2WB mem_wb (
        .clk(cpu_clock), .RST(rst_synced), .en_n(~ex_en),
        .bubble(1'b0), .sync_clear(1'b0), .halt_in(1'b0),
        .pc_in(exmem_pc), .alu_result_in(exmem_alu_result), .mem_data_in(mem_read_data),
        .ir_in(exmem_ir), .reserved1_in(exmem_reserved1), .reserved2_in(exmem_reserved2),
        .write_reg_in(exmem_write_reg), .decode_ctrl_in(exmem_decode_ctrl),
        .mem_to_reg_in(exmem_mem_to_reg), .reg_write_in(exmem_reg_write), .halt_out(),
        .interrupt_masked_out(), .pc_out(memwb_pc), .alu_result_out(memwb_alu_result),
        .mem_data_out(memwb_mem_data), .ir_out(memwb_ir), .reserved1_out(memwb_reserved1),
        .reserved2_out(memwb_reserved2), .write_reg_out(memwb_write_reg),
        .decode_ctrl_out(memwb_decode_ctrl), .mem_to_reg_out(memwb_mem_to_reg),
        .reg_write_out(memwb_reg_write)
    );

    // ================= ecall 显示锁存（a7==34 时显示 a0，锁存避免一闪而过） =================
    reg [31:0] led_latch;
    always @(posedge cpu_clock) begin
        if (rst_synced)
            led_latch <= 32'b0;
        else if (ex_en && ex_ecall_display)
            led_latch <= idex_rs2;
    end
    assign LedData = led_latch;

    // ================= 统计计数器（任务书要求：周期数/气泡数/load-use数/分支数） =================
    wire ex_is_jal  = idex_ir[6:0] == 7'b1101111;
    wire ex_is_jalr = idex_ir[6:2] == 5'b11001;
    always @(posedge cpu_clock) begin
        if (rst_synced) begin
            total_cycles  <= 16'b0;
            bubble_count  <= 16'b0;
            loaduse_count <= 16'b0;
            uncond_branch <= 16'b0;
            taken_branch  <= 16'b0;
        end else if (ex_en) begin
            total_cycles <= total_cycles + 16'd1;
            if (load_use_stall)
                loaduse_count <= loaduse_count + 16'd1;
            if (load_use_stall | redirect_control_valid | int_response)
                bubble_count <= bubble_count + 16'd1;
            if (ex_is_jal | ex_is_jalr)
                uncond_branch <= uncond_branch + 16'd1;
            if (ex_branch_taken)
                taken_branch <= taken_branch + 16'd1;
        end
    end

    // ================= 数码管显示（SW[2:0] 选择：000=显示值 001=总周期数 010=气泡数
    //                                    011=PC 100=LoadUse次数 101=无条件分支数 110=条件分支成功数
    //                                    111=MMIO SEG7 寄存器（游戏显示）） =================
    wire [31:0] display_data =
        DebugSel == 3'b000 ? LedData :
        DebugSel == 3'b001 ? {16'b0, total_cycles} :
        DebugSel == 3'b010 ? {16'b0, bubble_count} :
        DebugSel == 3'b011 ? if_pc :
        DebugSel == 3'b100 ? {16'b0, loaduse_count} :
        DebugSel == 3'b101 ? {16'b0, uncond_branch} :
        DebugSel == 3'b110 ? {16'b0, taken_branch} :
                             mmio_seg7;
    LedDisplay #(.CLOCK_INTERVAL(DISPLAY_CLOCK_INTERVAL)) led_display (
        .LedData(display_data), .CLK(CLK), .SEG(SEG), .AN(AN)
    );
endmodule

module IdealPipelineRiscV #(
    parameter integer CPU_CLOCK_INTERVAL = 1_000_000,
    parameter integer DISPLAY_CLOCK_INTERVAL = 50_000,   // 数码管扫描 100MHz/(2*50000)=1kHz，整轮刷新 125Hz
    parameter integer POR_CYCLES = 5_000_000,
    parameter integer ENABLE_REDIRECT = 1,
    parameter [31:0] INT_ADDR_1 = 32'h000000AC,
    parameter [31:0] INT_ADDR_2 = 32'h000001AC,
    parameter [31:0] INT_ADDR_3 = 32'h000002BC,
    parameter MEM_FILE = "../../mem/SimpleSingleCycleRiscV.mem"
    )(
    input         CLK,
    input         RST,
    input         Go,
    input         IR1,
    input         IR2,
    input         IR3,
    input  [2:0]  DebugSel,
    input  [15:0] SW,
    output        W1,
    output        W2,
    output        W3,
    output [15:0] LED,
    output [7:0]  SEG,
    output [7:0]  AN,
    output [31:0] PC,
    output [31:0] IR,
    output [31:0] RDin,
    output [31:0] MDin,
    output [31:0] LedData,
    output        RegWrite,
    output        MemWrite
    );

    PipelineRiscVCore #(
        .CPU_CLOCK_INTERVAL(CPU_CLOCK_INTERVAL),
        .DISPLAY_CLOCK_INTERVAL(DISPLAY_CLOCK_INTERVAL),
        .POR_CYCLES(POR_CYCLES),
        .ENABLE_REDIRECT(ENABLE_REDIRECT),
        .INT_ADDR_1(INT_ADDR_1), .INT_ADDR_2(INT_ADDR_2), .INT_ADDR_3(INT_ADDR_3),
        .MEM_FILE(MEM_FILE)
    ) core (
        .CLK(CLK), .RST(RST), .Go(Go), .IR1(IR1), .IR2(IR2), .IR3(IR3),
        .DebugSel(DebugSel), .SW(SW), .W1(W1), .W2(W2), .W3(W3), .LED(LED),
        .SEG(SEG), .AN(AN), .PC(PC), .IR(IR),
        .RDin(RDin), .MDin(MDin), .LedData(LedData),
        .RegWrite(RegWrite), .MemWrite(MemWrite)
    );
endmodule
