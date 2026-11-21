`timescale 1ns / 1ps

module ALU(
    input  [31:0] X,
    input  [31:0] Y,
    input  [3:0]  AluOP,
    output reg [31:0] Result,
    output reg [31:0] Result2,
    output Equal,
    output GreaterEqual,
    output GreaterEqualUnsigned,
    output Less
    );

    reg [63:0] product;

    assign Equal = (X == Y);
    assign GreaterEqual = ($signed(X) >= $signed(Y));
    assign GreaterEqualUnsigned = (X >= Y);
    assign Less = ($unsigned(X) < $unsigned(Y));

    always @(*) begin
        Result = 32'b0;
        Result2 = 32'b0;
        product = 64'b0;

        case (AluOP)
            4'd0:  Result = X << Y[4:0];
            4'd1:  Result = $signed(X) >>> Y[4:0];
            4'd2:  Result = X >> Y[4:0];
            4'd3: begin
                product = X * Y;
                Result = product[31:0];
                Result2 = product[63:32];
            end
            4'd4: begin
                if (Y != 32'b0) begin
                    Result = X / Y;
                    Result2 = X % Y;
                end
            end
            4'd5:  Result = X + Y;
            4'd6:  Result = X - Y;
            4'd7:  Result = X & Y;
            4'd8:  Result = X | Y;
            4'd9:  Result = X ^ Y;
            4'd10: Result = ~(X | Y);
            4'd11: Result = ($signed(X) < $signed(Y));
            4'd12: Result = ($unsigned(X) < $unsigned(Y));
        endcase
    end
endmodule
