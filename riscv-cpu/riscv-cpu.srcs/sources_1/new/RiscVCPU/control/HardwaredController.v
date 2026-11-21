`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/16 18:34:42
// Design Name: 
// Module Name: HardwaredController
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module HardwaredController(
    input  [31:0] IR,
    output [3:0]  ALU_OP,
    output        MemToReg,
    output        MemWrite,
    output        ALU_SRC,
    output        RegWrite,
    output        uret,
    output        ecall,
    output        S_type,
    output        Beq,
    output        Bne,
    output        Jalr,
    output        JAL,
    output        blt,
    output        csrrsi,
    output        dasb,
    output        U_type,
    output        csrrci
    );

    wire ecall_decode;

    ALU_OPGenerate alu_op_generate (
        .IR(IR),
        .ALUOP(ALU_OP)
    );

    ControlSignGenerate control_sign_generate (
        .IR(IR),
        .MemToReg(MemToReg),
        .MemWrite(MemWrite),
        .ALU_SRC(ALU_SRC),
        .RegWrite(RegWrite),
        .ecall(ecall_decode),
        .Stype(S_type),
        .Beq(Beq),
        .Bne(Bne),
        .Blt(blt),
        .JALR(Jalr),
        .JAL(JAL),
        .CSRRSI(csrrsi),
        .CSRRCI(csrrci),
        .Utype(U_type),
        .DASB(dasb)
    );

    assign uret = ecall_decode & IR[21];
    assign ecall = ecall_decode & ~IR[21];
endmodule
