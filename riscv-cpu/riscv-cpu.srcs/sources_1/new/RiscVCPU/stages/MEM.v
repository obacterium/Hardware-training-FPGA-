`timescale 1ns / 1ps

module MEM #(
    parameter integer MEMORY_WORDS = 1024
    )(
    input         cpu_clock,
    input         Go,
    input         MemWrite,
    input  [31:0] IR,
    input  [31:0] Address,
    input  [31:0] WriteData,
    output [31:0] ReadData
    );

    reg [31:0] data_memory [0:MEMORY_WORDS - 1];
    integer index;

    initial begin
        for (index = 0; index < MEMORY_WORDS; index = index + 1)
            data_memory[index] = 32'b0;
    end

    wire [2:0]  funct3  = IR[14:12];
    wire [31:0] aligned = Address & 32'hffff_fffc;
    wire [1:0]  offset  = Address[1:0];
    wire [31:0] mem_word = data_memory[aligned[11:2]];

    // ---------- 写数据组装（SB 字节 / SH 半字 / SW 字，读-改-写保留同字其余部分） ----------
    reg [31:0] store_word;
    always @(*) begin
        case (funct3)
            3'b000: case (offset)                    // SB
                2'b00: store_word = {mem_word[31:8],  WriteData[7:0]};
                2'b01: store_word = {mem_word[31:16], WriteData[7:0], mem_word[7:0]};
                2'b10: store_word = {mem_word[31:24], WriteData[7:0], mem_word[15:0]};
                2'b11: store_word = {WriteData[7:0],  mem_word[23:0]};
            endcase
            3'b001: store_word = offset[1] ? {WriteData[15:0], mem_word[15:0]}    // SH @+2
                                           : {mem_word[31:16], WriteData[15:0]}; // SH @+0
            default: store_word = WriteData;         // SW
        endcase
    end

    always @(posedge cpu_clock) begin
        if (Go && MemWrite)
            data_memory[aligned[11:2]] <= store_word;
    end

    // ---------- 读数据选择（LB/LBU/LH/LHU/LW + 符号/零扩展） ----------
    reg  [31:0] load_data;
    always @(*) begin
        case (funct3)
            3'b000: case (offset)                    // LB
                2'b00: load_data = {{24{mem_word[7]}},  mem_word[7:0]};
                2'b01: load_data = {{24{mem_word[15]}}, mem_word[15:8]};
                2'b10: load_data = {{24{mem_word[23]}}, mem_word[23:16]};
                2'b11: load_data = {{24{mem_word[31]}}, mem_word[31:24]};
            endcase
            3'b100: case (offset)                    // LBU
                2'b00: load_data = {24'b0, mem_word[7:0]};
                2'b01: load_data = {24'b0, mem_word[15:8]};
                2'b10: load_data = {24'b0, mem_word[23:16]};
                2'b11: load_data = {24'b0, mem_word[31:24]};
            endcase
            3'b001: load_data = offset[1] ? {{16{mem_word[31]}}, mem_word[31:16]}  // LH
                                          : {{16{mem_word[15]}}, mem_word[15:0]};
            3'b101: load_data = offset[1] ? {16'b0, mem_word[31:16]}               // LHU
                                          : {16'b0, mem_word[15:0]};
            default: load_data = mem_word;           // LW
        endcase
    end

    assign ReadData = load_data;
endmodule
