`timescale 1ns / 1ps

module PipelinengID2EX(
    input         clk,
    input         RST,
    input         en_n,
    input         bubble,
    input  [31:0] pc_in,
    input  [31:0] rs1_in,
    input  [31:0] rs2_in,
    input  [31:0] imm32_in,
    input  [31:0] imm_b_in,
    input  [31:0] imm_j_in,
    input  [31:0] ir_in,
    input  [4:0]  write_reg_in,
    input  [3:0]  alu_op_in,
    input  [9:0]  decode_ctrl_in,
    input         alu_src_in,
    input         mem_to_reg_in,
    input         mem_write_in,
    input         reg_write_in,
    input  [1:0]  rs1_fwd_in,
    input  [1:0]  rs2_fwd_in,
    input         predict_jump_in,
    output [31:0] pc_out,
    output [31:0] rs1_out,
    output [31:0] rs2_out,
    output [31:0] imm32_out,
    output [31:0] imm_b_out,
    output [31:0] imm_j_out,
    output [31:0] ir_out,
    output [4:0]  write_reg_out,
    output [3:0]  alu_op_out,
    output [9:0]  decode_ctrl_out,
    output        alu_src_out,
    output        mem_to_reg_out,
    output        mem_write_out,
    output        reg_write_out,
    output [1:0]  rs1_fwd_out,
    output [1:0]  rs2_fwd_out,
    output        predict_jump_out
    );

    reg [31:0] pc_reg, rs1_reg, rs2_reg, imm32_reg, imm_b_reg, imm_j_reg, ir_reg;
    reg [4:0]  write_reg_reg;
    reg [3:0]  alu_op_reg;
    reg [9:0]  decode_ctrl_reg;
    reg        alu_src_reg, mem_to_reg_reg, mem_write_reg, reg_write_reg;
    reg [1:0]  rs1_fwd_reg, rs2_fwd_reg;
    reg        predict_jump_reg;

    always @(posedge clk) begin
        if (RST) begin
            pc_reg           <= 32'b0;
            rs1_reg          <= 32'b0;
            rs2_reg          <= 32'b0;
            imm32_reg        <= 32'b0;
            imm_b_reg        <= 32'b0;
            imm_j_reg        <= 32'b0;
            ir_reg           <= 32'b0;
            write_reg_reg    <= 5'b0;
            alu_op_reg       <= 4'b0;
            decode_ctrl_reg  <= 10'b0;
            alu_src_reg      <= 1'b0;
            mem_to_reg_reg   <= 1'b0;
            mem_write_reg    <= 1'b0;
            reg_write_reg    <= 1'b0;
            rs1_fwd_reg      <= 2'b0;
            rs2_fwd_reg      <= 2'b0;
            predict_jump_reg <= 1'b0;
        end else if (!en_n) begin
            pc_reg           <= bubble ? 32'b0 : pc_in;
            rs1_reg          <= bubble ? 32'b0 : rs1_in;
            rs2_reg          <= bubble ? 32'b0 : rs2_in;
            imm32_reg        <= bubble ? 32'b0 : imm32_in;
            imm_b_reg        <= bubble ? 32'b0 : imm_b_in;
            imm_j_reg        <= bubble ? 32'b0 : imm_j_in;
            ir_reg           <= bubble ? 32'b0 : ir_in;
            write_reg_reg    <= bubble ? 5'b0  : write_reg_in;
            alu_op_reg       <= bubble ? 4'b0  : alu_op_in;
            decode_ctrl_reg  <= bubble ? 10'b0 : decode_ctrl_in;
            alu_src_reg      <= bubble ? 1'b0  : alu_src_in;
            mem_to_reg_reg   <= bubble ? 1'b0  : mem_to_reg_in;
            mem_write_reg    <= bubble ? 1'b0  : mem_write_in;
            reg_write_reg    <= bubble ? 1'b0  : reg_write_in;
            rs1_fwd_reg      <= bubble ? 2'b0  : rs1_fwd_in;
            rs2_fwd_reg      <= bubble ? 2'b0  : rs2_fwd_in;
            predict_jump_reg <= bubble ? 1'b0  : predict_jump_in;
        end
    end

    assign pc_out = pc_reg;
    assign rs1_out = rs1_reg;
    assign rs2_out = rs2_reg;
    assign imm32_out = imm32_reg;
    assign imm_b_out = imm_b_reg;
    assign imm_j_out = imm_j_reg;
    assign ir_out = ir_reg;
    assign write_reg_out = write_reg_reg;
    assign alu_op_out = alu_op_reg;
    assign decode_ctrl_out = decode_ctrl_reg;
    assign alu_src_out = alu_src_reg;
    assign mem_to_reg_out = mem_to_reg_reg;
    assign mem_write_out = mem_write_reg;
    assign reg_write_out = reg_write_reg;
    assign rs1_fwd_out = rs1_fwd_reg;
    assign rs2_fwd_out = rs2_fwd_reg;
    assign predict_jump_out = predict_jump_reg;
endmodule
