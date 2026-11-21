`timescale 1ns / 1ps

module SimpleSingleCycleRiscV #(
    parameter integer CPU_CLOCK_INTERVAL = 1_000_000,
    parameter integer DISPLAY_CLOCK_INTERVAL = 50_000,   // 数码管扫描 1kHz，整轮刷新 125Hz
    parameter integer POR_CYCLES = 5_000_000,            // 上电自动复位时长（CLK 周期数）
    parameter MEM_FILE = "../../mem/SimpleSingleCycleRiscV.mem"
    )(
    input         CLK,
    input         RST,
    input         Go,
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
    wire [31:0] pc_value, ir_value;
    wire [31:0] rs1, rs2, imm_i, imm_b, imm_j;
    wire [3:0] alu_op;
    wire alu_src, mem_to_reg, mem_write, reg_write;
    wire beq, bne, blt, jalr, jal, utype, stype, dasb;
    wire [4:0] write_reg;
    wire [31:0] alu_result, result2, store_data, memory_data, write_data;
    wire equal, branch_taken, redirect_valid;
    wire [31:0] redirect_pc;
    wire [4:0] wb_reg;
    wire wb_reg_write;
    wire ecall_display, ecall_halt;

    // ---------- 复位（上电自动复位 POR + 按键复位）与运行控制（复位后自动运行；ecall 停机→halt；Go 按下→继续） ----------
    reg [31:0] por_cnt = 32'b0;   // 初始化防止仿真 X 态（硬件 FF 上电亦为 0）
    wire por_active = (por_cnt < POR_CYCLES);
    always @(posedge CLK) begin
        if (por_active) por_cnt <= por_cnt + 32'd1;
    end
    reg rst_s1, rst_s2, go_s1, go_s2;
    always @(posedge CLK) begin rst_s1 <= por_active | RST; rst_s2 <= rst_s1; go_s1 <= Go; go_s2 <= go_s1; end
    wire rst_synced = rst_s2;

    reg running_ff, halt_ff;
    always @(posedge cpu_clock) begin
        if (rst_synced) begin
            running_ff <= 1'b1;   // 复位后自动开始运行（Go 仍用于 ecall 停机后的继续）
            halt_ff    <= 1'b0;
        end else begin
            if (go_s2) begin
                running_ff <= 1'b1;
                halt_ff    <= 1'b0;
            end else if (ecall_halt) begin
                halt_ff <= 1'b1;
            end
        end
    end
    wire run_en = running_ff & ~halt_ff;

    IF #(.CLOCK_INTERVAL(CPU_CLOCK_INTERVAL), .MEM_FILE(MEM_FILE)) instruction_fetch (
        .CLK(CLK), .RST(rst_synced), .Go(run_en),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .cpu_clock(cpu_clock), .PC(pc_value), .IR(ir_value)
    );

    ID instruction_decode (
        .cpu_clock(cpu_clock), .RST(rst_synced), .PC(pc_value), .IR(ir_value),
        .wb_enable(wb_reg_write & run_en), .wb_address(wb_reg), .wb_data(write_data),
        .RS1(rs1), .RS2(rs2), .ImmI(imm_i), .ImmB(imm_b), .ImmJ(imm_j),
        .ALU_OP(alu_op), .ALU_SRC(alu_src), .MemToReg(mem_to_reg),
        .MemWrite(mem_write), .RegWrite(reg_write), .Beq(beq), .Bne(bne),
        .Blt(blt), .JALR(jalr), .JAL(jal), .Utype(utype), .Stype(stype),
        .DASB(dasb), .WriteReg(write_reg)
    );

    EX execute (
        .PC(pc_value), .RS1(rs1), .RS2(rs2), .ImmI(imm_i), .ImmB(imm_b), .ImmJ(imm_j),
        .IR(ir_value), .EPC(32'b0),
        .ALU_OP(alu_op), .ALU_SRC(alu_src),
        .ALUResult(alu_result), .Result2(result2),
        .StoreData(store_data), .Equal(equal),
        .BranchTaken(branch_taken), .RedirectValid(redirect_valid),
        .RedirectPC(redirect_pc), .EcallDisplay(ecall_display),
        .EcallHalt(ecall_halt)
    );

    MEM memory_access (
        .cpu_clock(cpu_clock), .Go(run_en), .MemWrite(mem_write),
        .IR(ir_value), .Address(alu_result),
        .WriteData(store_data), .ReadData(memory_data)
    );

    WB writeback (
        .PC(pc_value), .IR(ir_value),
        .ALUResult(alu_result), .Result2(result2),
        .MemData(memory_data), .MemToReg(mem_to_reg),
        .RegWriteIn(reg_write), .WriteData(write_data),
        .RegWrite(wb_reg_write), .WriteReg(wb_reg)
    );

    // ecall 显示锁存：a7==34 → 显示 a0；否则停机
    reg [31:0] led_latch;
    always @(posedge cpu_clock) begin
        if (rst_synced)
            led_latch <= 32'b0;
        else if (run_en && ecall_display)
            led_latch <= rs2;
    end
    assign LedData = led_latch;

    assign PC = pc_value;
    assign IR = ir_value;
    assign RDin = write_data;
    assign MDin = store_data;
    assign RegWrite = wb_reg_write;
    assign MemWrite = mem_write;

    LedDisplay #(.CLOCK_INTERVAL(DISPLAY_CLOCK_INTERVAL)) led_display (
        .LedData(LedData), .CLK(CLK), .SEG(SEG), .AN(AN)
    );
endmodule
