`timescale 1ns / 1ps

module stage0_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire [15:0] led;
    wire [31:0] pc, ir, write_data;
    wire reg_write;
    reg saw_first_write = 1'b0;

    RedirectPipelineRiscV #(
        .CPU_CLOCK_INTERVAL(1),
        .DISPLAY_CLOCK_INTERVAL(1),
        .POR_CYCLES(20),
        .MEM_FILE("stage0.mem")
    ) dut (
        .CLK(clk), .RST(rst), .Go(1'b0),
        .IR1(1'b0), .IR2(1'b0), .IR3(1'b0),
        .DebugSel(3'b000), .SW(16'h8000),
        .W1(), .W2(), .W3(), .SEG(), .AN(), .MDin(), .LedData(), .MemWrite(),
        .LED(led), .PC(pc), .IR(ir), .RDin(write_data), .RegWrite(reg_write)
    );

    always #5 clk = ~clk;

    always @(posedge dut.pipeline.cpu_clock) begin
        if ((dut.pipeline.rst_synced === 1'b0) && (reg_write === 1'b1) &&
            (|dut.pipeline.wb_reg) && !saw_first_write) begin
            if (dut.pipeline.memwb_pc !== 32'd0 || dut.pipeline.wb_reg !== 5'd2 || write_data !== 32'h00008000)
                $fatal(1, "First writeback mismatch: PC=%08h rd=%0d value=%08h",
                    dut.pipeline.memwb_pc, dut.pipeline.wb_reg, write_data);
            saw_first_write <= 1'b1;
            $display("PASS: first writeback PC=00000000 x2=00008000");
        end
    end

    initial begin
        #100;
        if (pc !== 32'd0 || ir !== 32'h00008137)
            $fatal(1, "ROM word 0 mismatch: PC=%08h IR=%08h", pc, ir);
        $display("PASS: first fetch PC=00000000 IR=00008137");
        rst = 1'b0;

        wait (led === 16'h600d || led === 16'h0101 || led === 16'h0102);
        if (!saw_first_write || led !== 16'h600d)
            $fatal(1, "Stage 0 failed: LED=%04h first_write=%b", led, saw_first_write);
        if (dut.pipeline.memory_access.data_memory[32'h7000 >> 2] !== 32'h13579bdf ||
            dut.pipeline.memory_access.data_memory[32'h7004 >> 2] !== 32'h00000000 ||
            dut.pipeline.memory_access.data_memory[32'h7ff0 >> 2] !== 32'h2468ace0)
            $fatal(1, "RAM probe wrote unexpected data");
        $display("PASS: stage0 RTL LED=600d (RAM probe and SYS_ID)");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Stage 0 timed out: PC=%08h LED=%04h", pc, led);
    end
endmodule
