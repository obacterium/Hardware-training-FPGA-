`timescale 1ns / 1ps

module RegUse(
    input  [4:0] OP,
    input  [4:0] Funct,
    input        INT,
    output       rs1_used,
    output       rs2_used
    );

    wire is_r_type = OP == 5'b01100;
    wire is_i_type = OP == 5'b00100;
    wire is_load = OP == 5'b00000;
    wire is_store = OP == 5'b01000;
    wire is_branch = OP == 5'b11000;
    wire is_jalr = OP == 5'b11001;
    wire is_system = OP == 5'b11100;
    wire interrupt_instruction = INT & (Funct == 5'b00000);

    assign rs1_used = is_r_type | is_i_type | is_load | is_store |
                      is_branch | is_jalr | (is_system & interrupt_instruction);
    assign rs2_used = is_r_type | is_store | is_branch;
endmodule
