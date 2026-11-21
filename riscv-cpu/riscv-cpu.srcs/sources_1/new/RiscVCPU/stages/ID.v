`timescale 1ns / 1ps

module ID(
    input         cpu_clock,
    input         RST,
    input  [31:0] PC,
    input  [31:0] IR,
    input         wb_enable,
    input  [4:0]  wb_address,
    input  [31:0] wb_data,
    output [31:0] RS1,
    output [31:0] RS2,
    output [31:0] ImmI,
    output [31:0] ImmB,
    output [31:0] ImmJ,
    output [3:0]  ALU_OP,
    output        ALU_SRC,
    output        MemToReg,
    output        MemWrite,
    output        RegWrite,
    output        Beq,
    output        Bne,
    output        Blt,
    output        JALR,
    output        JAL,
    output        Utype,
    output        Stype,
    output        DASB,
    output [4:0]  WriteReg,
    output [4:0]  rs1_id,
    output [4:0]  rs2_id,
    output        rs1_used,
    output        rs2_used
    );

    wire uret_unused, ecall_unused, csrrsi_unused, csrrci_unused;
    wire [4:0] rs1_address = IR[19:15];
    wire [4:0] rs2_address = IR[24:20];
    wire [4:0] funct = {IR[30], IR[25], IR[14:12]};
    wire rs1_used_raw, rs2_used_raw;

    // ecall 需要读 a7(x17) 与 a0(x10)：读地址覆盖 + 参与冒险检测
    wire is_ecall = (IR[6:2] == 5'b11100) && (IR[14:12] == 3'b000) && ~IR[21];
    wire [4:0] rf_rs1 = is_ecall ? 5'd17 : rs1_address;
    wire [4:0] rf_rs2 = is_ecall ? 5'd10 : rs2_address;

    HardwaredController controller (
        .IR(IR), .ALU_OP(ALU_OP), .MemToReg(MemToReg), .MemWrite(MemWrite),
        .ALU_SRC(ALU_SRC), .RegWrite(RegWrite), .uret(uret_unused),
        .ecall(ecall_unused), .S_type(Stype), .Beq(Beq), .Bne(Bne),
        .Jalr(JALR), .JAL(JAL), .blt(Blt), .csrrsi(csrrsi_unused),
        .dasb(DASB), .U_type(Utype), .csrrci(csrrci_unused)
    );

    RegFile registers (
        .Clk(cpu_clock), .RST(RST),
        .WE(wb_enable), .Din(wb_data), .\W# (wb_address),
        .\R1# (rf_rs1), .\R2# (rf_rs2),
        .R1(RS1), .R2(RS2)
    );

    RegUse register_usage (
        .OP(IR[6:2]), .Funct(funct), .INT(1'b0),
        .rs1_used(rs1_used_raw), .rs2_used(rs2_used_raw)
    );

    assign WriteReg = IR[11:7];
    assign rs1_id = rf_rs1;
    assign rs2_id = rf_rs2;
    assign rs1_used = rs1_used_raw | is_ecall;
    assign rs2_used = rs2_used_raw | is_ecall;
    assign ImmI = {{20{IR[31]}}, IR[31:20]};
    assign ImmB = {{19{IR[31]}}, IR[31], IR[7], IR[30:25], IR[11:8], 1'b0};
    assign ImmJ = {{11{IR[31]}}, IR[31], IR[19:12], IR[20], IR[30:21], 1'b0};
endmodule
