`timescale 1ns / 1ps

module LedDisplay #(
    parameter integer CLOCK_INTERVAL = 1_000_000
    )(
    input  [31:0] LedData,
    input         CLK,
    output reg [7:0] SEG,
    output reg [7:0] AN
    );

    reg [2:0] digit_index = 3'b0;
    reg [3:0] digit_data;
    wire display_clock;

    Divider #(
        .CLOCK_INTERVAL(CLOCK_INTERVAL)
    ) display_divider (
        .CLK(CLK), .DividedCLK(display_clock)
    );

    always @(posedge display_clock) begin
        digit_index <= digit_index + 1'b1;
    end

    always @(*) begin
        AN = ~(8'b00000001 << digit_index);
        digit_data = LedData[digit_index * 4 +: 4];

        case (digit_data)
            4'h0: SEG = 8'b11000000;
            4'h1: SEG = 8'b11111001;
            4'h2: SEG = 8'b10100100;
            4'h3: SEG = 8'b10110000;
            4'h4: SEG = 8'b10011001;
            4'h5: SEG = 8'b10010010;
            4'h6: SEG = 8'b10000010;
            4'h7: SEG = 8'b11111000;
            4'h8: SEG = 8'b10000000;
            4'h9: SEG = 8'b10010000;
            4'hA: SEG = 8'b10001000;
            4'hB: SEG = 8'b10000011;
            4'hC: SEG = 8'b11000110;
            4'hD: SEG = 8'b10100001;
            4'hE: SEG = 8'b10000110;
            4'hF: SEG = 8'b10001110;
            default: SEG = 8'b11111111;
        endcase
    end
endmodule