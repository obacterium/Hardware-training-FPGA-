`timescale 1ns / 1ps

module RedirectPipelineRiscV #(
    parameter integer CPU_CLOCK_INTERVAL = 1_000_000,
    parameter integer DISPLAY_CLOCK_INTERVAL = 50_000,   // 数码管扫描 1kHz，整轮刷新 125Hz
    parameter integer POR_CYCLES = 5_000_000,
    parameter [31:0] INT_ADDR_1 = 32'h000000AC,
    parameter [31:0] INT_ADDR_2 = 32'h000001AC,
    parameter [31:0] INT_ADDR_3 = 32'h000002BC,
    parameter MEM_FILE = "../../mem/SimpleSingleCycleRiscV.mem"
    )(
    input         CLK,
    input         RST,
    input         Go,
    input         IR1,
    input         IR2,
    input         IR3,
    input  [2:0]  DebugSel,
    output        W1,
    output        W2,
    output        W3,
    output [7:0]  SEG,
    output [7:0]  AN,
    output [31:0] PC,
    output [31:0] IR,
    output [31:0] RDin,
    output [31:0] MDin,
    output [31:0] LedData,
    output        RegWrite,
    output        MemWrite
    );

    PipelineRiscVCore #(
        .CPU_CLOCK_INTERVAL(CPU_CLOCK_INTERVAL),
        .DISPLAY_CLOCK_INTERVAL(DISPLAY_CLOCK_INTERVAL),
        .POR_CYCLES(POR_CYCLES),
        .ENABLE_REDIRECT(1),
        .INT_ADDR_1(INT_ADDR_1), .INT_ADDR_2(INT_ADDR_2), .INT_ADDR_3(INT_ADDR_3),
        .MEM_FILE(MEM_FILE)
    ) pipeline (
        .CLK(CLK), .RST(RST), .Go(Go), .IR1(IR1), .IR2(IR2), .IR3(IR3),
        .DebugSel(DebugSel), .W1(W1), .W2(W2), .W3(W3),
        .SEG(SEG), .AN(AN), .PC(PC), .IR(IR),
        .RDin(RDin), .MDin(MDin), .LedData(LedData),
        .RegWrite(RegWrite), .MemWrite(MemWrite)
    );
endmodule
