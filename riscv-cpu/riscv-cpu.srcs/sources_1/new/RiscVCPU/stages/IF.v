`timescale 1ns / 1ps

module IF #(
    parameter integer CLOCK_INTERVAL = 1_000_000,
    parameter integer MEMORY_WORDS = 4096,   // 指令 ROM 4K 字 = 16KB（外设接入扩容，见 INTERFACE.md §7）
    parameter MEM_FILE = "../../mem/InterruptTest_fixed.mem"
    )(
    input         CLK,
    input         RST,
    input         Go,
    input         redirect_valid,
    input  [31:0] redirect_pc,
    output        cpu_clock,
    output [31:0] PC,
    output [31:0] IR
    );

    reg [31:0] program_counter = 32'b0;
    reg [31:0] instruction_memory [0:MEMORY_WORDS - 1];
    integer index;

    initial begin
        for (index = 0; index < MEMORY_WORDS; index = index + 1)
            instruction_memory[index] = 32'b0;
        $readmemh(MEM_FILE, instruction_memory);
    end

    Divider #(.CLOCK_INTERVAL(CLOCK_INTERVAL)) divider (
        .CLK(CLK), .DividedCLK(cpu_clock)
    );

    always @(posedge cpu_clock) begin
        if (RST) begin
            program_counter <= 32'b0;
        end else if (Go) begin
            if (redirect_valid)
                program_counter <= redirect_pc;
            else
                program_counter <= program_counter + 32'd4;
        end
    end

    assign PC = program_counter;
    assign IR = instruction_memory[program_counter[13:2]];
endmodule
