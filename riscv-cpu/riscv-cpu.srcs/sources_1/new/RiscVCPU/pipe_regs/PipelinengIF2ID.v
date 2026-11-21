`timescale 1ns / 1ps

module PipelinengIF2ID(
    input         clk,
    input         RST,
    input         en_n,
    input         bubble,
    input         predict_jump_in,
    input  [31:0] ir_in,
    input  [31:0] pc_in,
    output        predict_jump_out,
    output [31:0] ir_out,
    output [31:0] ir_debug_out,
    output [31:0] pc_out
    );

    reg        predict_jump_reg;
    reg [31:0] ir_reg;
    reg [31:0] pc_reg;

    always @(posedge clk) begin
        if (RST) begin
            predict_jump_reg <= 1'b0;
            ir_reg           <= 32'b0;
            pc_reg           <= 32'b0;
        end else if (!en_n) begin
            predict_jump_reg <= bubble ? 1'b0  : predict_jump_in;
            ir_reg           <= bubble ? 32'b0 : ir_in;
            pc_reg           <= bubble ? 32'b0 : pc_in;
        end
    end

    assign predict_jump_out = predict_jump_reg;
    assign ir_out = ir_reg;
    assign ir_debug_out = ir_reg;
    assign pc_out = pc_reg;
endmodule
