`timescale 1ns / 1ps

// 数据相关监测 + 三级转发选择（EX / MEM / WB，近者优先）
//   rs1Fwd/rs2Fwd: 00=无相关(取寄存器堆) 01=EX转发 10=MEM转发 11=WB转发
module DataWatch(
    input  [4:0] rs1_id,
    input  [4:0] rs2_id,
    input        rs1_used_in,
    input        rs2_used_in,
    input        ex_reg_write,
    input        mem_reg_write,
    input        wb_reg_write,
    input        ex_mem_to_reg,
    input  [4:0] ex_rd,
    input  [4:0] mem_rd,
    input  [4:0] wb_rd,
    output [1:0] rs1Fwd,
    output       DataCorrelate,
    output [1:0] rs2Fwd,
    output       LoadUse
    );

    wire ex_rs1_correlate = rs1_used_in && ex_reg_write &&
                            (ex_rd != 5'b0) && (rs1_id == ex_rd);
    wire mem_rs1_correlate = rs1_used_in && mem_reg_write &&
                             (mem_rd != 5'b0) && (rs1_id == mem_rd);
    wire wb_rs1_correlate = rs1_used_in && wb_reg_write &&
                            (wb_rd != 5'b0) && (rs1_id == wb_rd);
    wire ex_rs2_correlate = rs2_used_in && ex_reg_write &&
                            (ex_rd != 5'b0) && (rs2_id == ex_rd);
    wire mem_rs2_correlate = rs2_used_in && mem_reg_write &&
                             (mem_rd != 5'b0) && (rs2_id == mem_rd);
    wire wb_rs2_correlate = rs2_used_in && wb_reg_write &&
                            (wb_rd != 5'b0) && (rs2_id == wb_rd);

    assign rs1Fwd = ex_rs1_correlate ? 2'b01 :
                    mem_rs1_correlate ? 2'b10 :
                    wb_rs1_correlate ? 2'b11 : 2'b00;
    assign rs2Fwd = ex_rs2_correlate ? 2'b01 :
                    mem_rs2_correlate ? 2'b10 :
                    wb_rs2_correlate ? 2'b11 : 2'b00;
    assign DataCorrelate = ex_rs1_correlate || mem_rs1_correlate || wb_rs1_correlate ||
                           ex_rs2_correlate || mem_rs2_correlate || wb_rs2_correlate;
    // Load-Use：EX 段是取数指令且 ID 段指令用其目的寄存器 → 插一拍气泡
    assign LoadUse = ex_mem_to_reg && (ex_rd != 5'b0) &&
                     ((rs1_used_in && (rs1_id == ex_rd)) ||
                      (rs2_used_in && (rs2_id == ex_rd)));
endmodule
