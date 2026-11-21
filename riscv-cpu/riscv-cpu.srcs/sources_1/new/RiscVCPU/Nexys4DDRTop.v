`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Nexys4 DDR 顶层
//   按键分配：BTNU=RST 复位 | BTNC=Go 运行/继续 | BTNL=IR1 | BTNR=IR2 | BTND=IR3 中断源
//   显示：SW[2:0] 选择数码管内容（000=显示值 001=总周期数 010=气泡数 011=PC
//                                     100=LoadUse次数 101=无条件分支数 110=条件分支成功数）
//        LED[15]=W3 LED[14]=W2 LED[13]=W1（中断等待指示），LED[12:0]=PC[12:0]
//////////////////////////////////////////////////////////////////////////////////


module Nexys4DDRTop(
    input         CLK,
    input         RST,
    input         Go,
    input         IR1,
    input         IR2,
    input         IR3,
    input  [15:0] SW,
    output [7:0]  SEG,
    output [7:0]  AN,
    output [15:0] LED
    );

    wire [31:0] program_counter;
    wire [31:0] instruction;
    wire [31:0] register_write_data;
    wire [31:0] memory_write_data;
    wire [31:0] led_data;
    wire        register_write;
    wire        memory_write;
    wire        w1, w2, w3;

    RedirectPipelineRiscV #(
        .MEM_FILE("../../mem/InterruptTest_fixed.mem")   // 补丁版中断测试（ISR 现场保护已补全，入口 0xAC/0x1AC/0x2BC）；路径相对 stages/IF.v 所在目录解析
    ) cpu (
        .CLK(CLK), .RST(RST), .Go(Go),
        .IR1(IR1), .IR2(IR2), .IR3(IR3),
        .DebugSel(SW[2:0]),
        .W1(w1), .W2(w2), .W3(w3),
        .SEG(SEG), .AN(AN),
        .PC(program_counter), .IR(instruction),
        .RDin(register_write_data), .MDin(memory_write_data),
        .LedData(led_data), .RegWrite(register_write), .MemWrite(memory_write)
    );

    assign LED = {w3, w2, w1, program_counter[12:0]};
endmodule
