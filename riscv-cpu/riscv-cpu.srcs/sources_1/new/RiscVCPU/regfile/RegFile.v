`timescale 1ns / 1ps

module RegFile(
    input         Clk,
    input         RST,
    input         WE,
    input  [31:0] Din,
    input  [4:0]  \W# ,
    input  [4:0]  \R1# ,
    input  [4:0]  \R2# ,
    output [31:0] R1,
    output [31:0] R2
    );

    reg [31:0] registers [0:31];
    integer index;

    initial begin
        for (index = 0; index < 32; index = index + 1)
            registers[index] = 32'b0;
    end

    always @(posedge Clk) begin
        if (RST) begin
            registers[1]  <= 32'b0;
            registers[2]  <= 32'b0;
            registers[3]  <= 32'b0;
            registers[4]  <= 32'b0;
            registers[5]  <= 32'b0;
            registers[6]  <= 32'b0;
            registers[7]  <= 32'b0;
            registers[8]  <= 32'b0;
            registers[9]  <= 32'b0;
            registers[10] <= 32'b0;
            registers[11] <= 32'b0;
            registers[12] <= 32'b0;
            registers[13] <= 32'b0;
            registers[14] <= 32'b0;
            registers[15] <= 32'b0;
            registers[16] <= 32'b0;
            registers[17] <= 32'b0;
            registers[18] <= 32'b0;
            registers[19] <= 32'b0;
            registers[20] <= 32'b0;
            registers[21] <= 32'b0;
            registers[22] <= 32'b0;
            registers[23] <= 32'b0;
            registers[24] <= 32'b0;
            registers[25] <= 32'b0;
            registers[26] <= 32'b0;
            registers[27] <= 32'b0;
            registers[28] <= 32'b0;
            registers[29] <= 32'b0;
            registers[30] <= 32'b0;
            registers[31] <= 32'b0;
        end else if (WE && \W#  != 5'b0) begin
            registers[\W# ] <= Din;
        end
    end

    // x0 恒为 0（RISC-V 规范要求）
    assign R1 = (\R1#  == 5'b0) ? 32'b0 : registers[\R1# ];
    assign R2 = (\R2#  == 5'b0) ? 32'b0 : registers[\R2# ];
endmodule
