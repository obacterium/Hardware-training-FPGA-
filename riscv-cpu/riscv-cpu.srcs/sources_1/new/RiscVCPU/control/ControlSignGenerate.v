`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 控制信号生成逻辑（完整版：24 条基本指令 + CCAB 扩展指令全集）
// functOP = {IR[30], IR[26], IR[25], IR[14:12], IR[6:2]}（11 位）
// 增加 IR[26] 是为了区分 funct7=0000001（MUL/DIVU/REMU）与 funct7=0000000（ADD/SLL 等）
//////////////////////////////////////////////////////////////////////////////////


module ControlSignGenerate(
    input   [31:0]  IR,
    output  reg     MemToReg,
    output  reg     MemWrite,
    output  reg     ALU_SRC,
    output  reg     RegWrite,
    output  reg     ecall,
    output  reg     Stype,
    output  reg     Beq,
    output  reg     Bne,
    output  reg     Blt,
    output  reg     JALR,
    output  reg     JAL,
    output  reg     CSRRSI,
    output  reg     CSRRCI,
    output  reg     Utype,
    output  reg     DASB
    );
    reg [10:0] functOP;

    always @(*) functOP = {IR[30], IR[26], IR[25], IR[14:12], IR[6:2]};

    always @(*) begin
        MemToReg = 0;
        MemWrite = 0;
        ALU_SRC = 0;
        RegWrite = 0;
        ecall = 0;
        Stype = 0;
        Beq = 0;
        Bne = 0;
        Blt = 0;
        JALR = 0;
        JAL = 0;
        CSRRSI = 0;
        CSRRCI = 0;
        DASB = 0;
        Utype = 0;

        casez (functOP)
            // ---------- I 型运算 ----------
            11'b???00000100: begin ALU_SRC = 1; RegWrite = 1; end  // ADDI
            11'b???11100100: begin ALU_SRC = 1; RegWrite = 1; end  // ANDI
            11'b???11000100: begin ALU_SRC = 1; RegWrite = 1; end  // ORI
            11'b???10000100: begin ALU_SRC = 1; RegWrite = 1; end  // XORI
            11'b???01000100: begin ALU_SRC = 1; RegWrite = 1; end  // SLTI
            11'b???01100100: begin ALU_SRC = 1; RegWrite = 1; end  // SLTIU
            11'b00000100100: begin ALU_SRC = 1; RegWrite = 1; end  // SLLI
            11'b00010100100: begin ALU_SRC = 1; RegWrite = 1; end  // SRLI
            11'b10010100100: begin ALU_SRC = 1; RegWrite = 1; end  // SRAI
            // ---------- 访存 ----------
            11'b???00000000: begin MemToReg = 1; ALU_SRC = 1; RegWrite = 1; end  // LB
            11'b???10000000: begin MemToReg = 1; ALU_SRC = 1; RegWrite = 1; end  // LBU
            11'b???00100000: begin MemToReg = 1; ALU_SRC = 1; RegWrite = 1; end  // LH
            11'b???10100000: begin MemToReg = 1; ALU_SRC = 1; RegWrite = 1; end  // LHU
            11'b???01000000: begin MemToReg = 1; ALU_SRC = 1; RegWrite = 1; end  // LW
            11'b???00001000: begin MemWrite = 1; ALU_SRC = 1; Stype = 1; DASB = 1; end  // SB
            11'b???00101000: begin MemWrite = 1; ALU_SRC = 1; Stype = 1; end  // SH
            11'b???01001000: begin MemWrite = 1; ALU_SRC = 1; Stype = 1; end  // SW
            // ---------- 分支 ----------
            11'b???00011000: Beq = 1;  // BEQ
            11'b???00111000: Bne = 1;  // BNE
            11'b???10011000: Blt = 1;  // BLT
            11'b???10111000: ;         // BGE  (EX 段按 IR[14:12] 判定)
            11'b???11011000: ;         // BLTU (EX 段按 IR[14:12] 判定)
            11'b???11111000: ;         // BGEU (EX 段按 IR[14:12] 判定)
            // ---------- 跳转 ----------
            11'b??????11011: begin JAL = 1;  RegWrite = 1; end  // JAL
            11'b???00011001: begin JALR = 1; RegWrite = 1; end  // JALR
            // ---------- 系统 ----------
            11'b00000011100: ecall = 1;      // ECALL/URET（HardwaredController 按 IR[21] 区分）
            11'b???11011100: CSRRSI = 1;     // CSRRSI（简化为开中断）
            11'b???11111100: CSRRCI = 1;     // CSRRCI（简化为关中断）
            // ---------- U 型 ----------
            11'b??????01101: begin Utype = 1; RegWrite = 1; end  // LUI
            11'b??????00101: begin RegWrite = 1; end              // AUIPC
            // ---------- R 型 ----------
            11'b00000001100: RegWrite = 1;  // ADD
            11'b10000001100: RegWrite = 1;  // SUB
            11'b00000101100: RegWrite = 1;  // SLL
            11'b00010101100: RegWrite = 1;  // SRL
            11'b10010101100: RegWrite = 1;  // SRA
            11'b00010001100: RegWrite = 1;  // XOR
            11'b00011101100: RegWrite = 1;  // AND
            11'b00011001100: RegWrite = 1;  // OR
            11'b00001001100: RegWrite = 1;  // SLT
            11'b00001101100: RegWrite = 1;  // SLTU
            11'b00100001100: RegWrite = 1;  // MUL
            11'b00110101100: RegWrite = 1;  // DIVU
            11'b00111101100: RegWrite = 1;  // REMU
            default: ;
        endcase
    end

endmodule
