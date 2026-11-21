`timescale 1ns / 1ps

module Divider #(
    parameter integer CLOCK_INTERVAL = 1_000_000
    )(
    input  CLK,
    output reg DividedCLK = 1'b0
    );

    reg [31:0] clock_count = 32'b0;

    always @(posedge CLK) begin
        if (clock_count == CLOCK_INTERVAL - 1) begin
            clock_count <= 32'b0;
            DividedCLK <= ~DividedCLK;
        end else begin
            clock_count <= clock_count + 1'b1;
        end
    end
endmodule