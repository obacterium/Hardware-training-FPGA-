`timescale 1ns / 1ps

module WB(
    input  [31:0] PC,
    input  [31:0] IR,
    input  [31:0] ALUResult,
    input  [31:0] Result2,
    input  [31:0] MemData,
    input         MemToReg,
    input         RegWriteIn,
    output [31:0] WriteData,
    output        RegWrite,
    output [4:0]  WriteReg
    );

    wire is_jal   = IR[6:0] == 7'b1101111;
    wire is_jalr  = IR[6:0] == 7'b1100111;
    wire is_lui   = IR[6:0] == 7'b0110111;
    wire is_auipc = IR[6:0] == 7'b0010111;
    wire is_remu  = (IR[6:0] == 7'b0110011) && (IR[14:12] == 3'b111) &&
                    (IR[31:25] == 7'b0000001);

    assign WriteData = (is_jal | is_jalr) ? PC + 32'd4 :
                       is_lui             ? {IR[31:12], 12'b0} :
                       is_auipc           ? PC + {IR[31:12], 12'b0} :
                       is_remu            ? Result2 :
                       MemToReg           ? MemData : ALUResult;
    assign RegWrite = RegWriteIn;
    assign WriteReg = IR[11:7];
endmodule
