`timescale 1ns / 1ps

module PipelinengMEM2WB(
    input         clk,
    input         RST,
    input         en_n,
    input         bubble,
    input         sync_clear,
    input         halt_in,
    input  [31:0] pc_in,
    input  [31:0] alu_result_in,
    input  [31:0] mem_data_in,
    input  [31:0] ir_in,
    input  [31:0] reserved1_in,
    input  [31:0] reserved2_in,
    input  [4:0]  write_reg_in,
    input  [9:0]  decode_ctrl_in,
    input         mem_to_reg_in,
    input         reg_write_in,
    output        halt_out,
    output        interrupt_masked_out,
    output [31:0] pc_out,
    output [31:0] alu_result_out,
    output [31:0] mem_data_out,
    output [31:0] ir_out,
    output [31:0] reserved1_out,
    output [31:0] reserved2_out,
    output [4:0]  write_reg_out,
    output [9:0]  decode_ctrl_out,
    output        mem_to_reg_out,
    output        reg_write_out
    );

    reg halt_reg, interrupt_masked_reg;
    reg [31:0] pc_reg, alu_result_reg, mem_data_reg, ir_reg, reserved1_reg, reserved2_reg;
    reg [4:0] write_reg_reg;
    reg [9:0] decode_ctrl_reg;
    reg mem_to_reg_reg, reg_write_reg;

    always @(posedge clk) begin
        if (RST) begin
            halt_reg              <= 1'b0;
            interrupt_masked_reg  <= 1'b0;
            pc_reg                <= 32'b0;
            alu_result_reg        <= 32'b0;
            mem_data_reg          <= 32'b0;
            ir_reg                <= 32'b0;
            reserved1_reg         <= 32'b0;
            reserved2_reg         <= 32'b0;
            write_reg_reg         <= 5'b0;
            decode_ctrl_reg       <= 10'b0;
            mem_to_reg_reg        <= 1'b0;
            reg_write_reg         <= 1'b0;
        end else if (!en_n) begin
            halt_reg              <= (bubble | sync_clear) ? 1'b0  : halt_in;
            interrupt_masked_reg  <= (bubble | sync_clear) ? 1'b0  : halt_in;
            pc_reg                <= (bubble | sync_clear) ? 32'b0 : pc_in;
            alu_result_reg        <= (bubble | sync_clear) ? 32'b0 : alu_result_in;
            mem_data_reg          <= (bubble | sync_clear) ? 32'b0 : mem_data_in;
            ir_reg                <= (bubble | sync_clear) ? 32'b0 : ir_in;
            reserved1_reg         <= (bubble | sync_clear) ? 32'b0 : reserved1_in;
            reserved2_reg         <= (bubble | sync_clear) ? 32'b0 : reserved2_in;
            write_reg_reg         <= (bubble | sync_clear) ? 5'b0  : write_reg_in;
            decode_ctrl_reg       <= (bubble | sync_clear) ? 10'b0 : decode_ctrl_in;
            mem_to_reg_reg        <= (bubble | sync_clear) ? 1'b0  : mem_to_reg_in;
            reg_write_reg         <= (bubble | sync_clear) ? 1'b0  : reg_write_in;
        end
    end

    assign halt_out = halt_reg;
    assign interrupt_masked_out = interrupt_masked_reg;
    assign pc_out = pc_reg;
    assign alu_result_out = alu_result_reg;
    assign mem_data_out = mem_data_reg;
    assign ir_out = ir_reg;
    assign reserved1_out = reserved1_reg;
    assign reserved2_out = reserved2_reg;
    assign write_reg_out = write_reg_reg;
    assign decode_ctrl_out = decode_ctrl_reg;
    assign mem_to_reg_out = mem_to_reg_reg;
    assign reg_write_out = reg_write_reg;
endmodule
