`timescale 1ns / 1ps

// CASE 0 uses only the repository RTL. The other cases add a simulation-only
// framebuffer and PS/2 FIFO at the addresses specified in INTERFACE.md.
module firmware_tb #(
    parameter integer TEST_CASE = 0,
    parameter IMAGE = "diag_mmio.mem",
    parameter DEMO = 0
);
    reg clk = 0, rst = 1;
    reg [15:0] switches = 16'h8127;
    wire [15:0] led;
    wire [31:0] pc;

    RedirectPipelineRiscV #(
        .CPU_CLOCK_INTERVAL(1), .DISPLAY_CLOCK_INTERVAL(1),
        .POR_CYCLES(20), .MEM_FILE(IMAGE)
    ) dut (
        .CLK(clk), .RST(rst), .Go(1'b0), .IR1(1'b0), .IR2(1'b0), .IR3(1'b0),
        .DebugSel(switches[2:0]), .SW(switches), .LED(led), .PC(pc),
        .W1(), .W2(), .W3(), .SEG(), .AN(), .IR(), .RDin(), .MDin(), .LedData(),
        .RegWrite(), .MemWrite()
    );
    always #5 clk = ~clk;

    wire cpu_clock = dut.pipeline.cpu_clock;
    wire [31:0] address = dut.pipeline.exmem_alu_result;
    wire [31:0] write_data = dut.pipeline.exmem_write_data;
    wire [2:0] access_size = dut.pipeline.exmem_ir[14:12];
    wire access_active = dut.pipeline.ex_en && !dut.pipeline.rst_synced;
    wire store = access_active && dut.pipeline.exmem_mem_write;
    wire load = access_active && dut.pipeline.exmem_mem_to_reg;
    wire register_select = address[31:12] == 20'hffff0;
    wire [31:0] seg_value = dut.pipeline.mmio_seg7;

    reg [15:0] framebuffer [0:2399];
    reg [7:0] fifo [0:15];
    integer fifo_in = 0, fifo_out = 0, fifo_used = 0;
    reg overflow = 0;
    reg [31:0] tick = 32'hfffffff0;
    reg [31:0] rng = DEMO ? 0 : 1;
    wire [7:0] fifo_count = fifo_used;
    wire fifo_empty = fifo_used == 0;
    wire fifo_full = fifo_used == 16;
    wire [31:0] model_read =
        address == 32'hffff0018 ? (fifo_empty ? 32'd0 : {24'd0, fifo[fifo_out]}) :
        address == 32'hffff001c ? {16'd0, fifo_count, 5'd0, overflow, fifo_full, fifo_empty} :
        TEST_CASE == 3 && address == 32'hffff0010 ? tick :
        TEST_CASE == 3 && address == 32'hffff0020 ? rng :
        dut.pipeline.mmio_periph.read_mux;

    generate if (TEST_CASE != 0) begin : peripheral_model
        initial begin
            force dut.pipeline.mmio_read_data = model_read;
            // Prevent the baseline register decoder from also accepting framebuffer writes.
            force dut.pipeline.mmio_periph.mmio_sel = register_select;
        end
    end endgenerate

    integer cycles = 0, pops = 0, status_reads = 0, tick_reads = 0;
    integer overflows_read = 0, framebuffer_writes = 0, cell_index;
    integer last_frame_cycles = 0, max_frame_cycles = 0;
    integer last_frame_writes = 0, clear_cycles = 0, clear_writes = 0;
    integer four_clear_cycles = 0, four_clear_writes = 0;
    wire [31:0] game_mode = dut.pipeline.memory_access.data_memory[64];
    wire [31:0] score = dut.pipeline.memory_access.data_memory[65];
    wire [31:0] lines = dut.pipeline.memory_access.data_memory[66];
    wire [31:0] piece = dut.pipeline.memory_access.data_memory[70];
    wire [31:0] rotation = dut.pipeline.memory_access.data_memory[71];
    wire [31:0] game_x = dut.pipeline.memory_access.data_memory[72];
    wire [31:0] game_y = dut.pipeline.memory_access.data_memory[73];
    wire [31:0] key_resync = dut.pipeline.memory_access.data_memory[86];

    always @(posedge cpu_clock) begin
        cycles <= cycles + 1;
        if (TEST_CASE != 0 && store && address >= 32'hffff1000 && address <= 32'hffff22bf) begin
            cell_index = (address - 32'hffff1000) >> 1;
            if (access_size == 3'b010 && address[1:0] == 0) begin
                framebuffer[cell_index] <= write_data[15:0];
                framebuffer[cell_index + 1] <= write_data[31:16];
            end else if (access_size == 3'b001 && address[0] == 0) begin
                framebuffer[cell_index] <= write_data[15:0];
            end else begin
                $fatal(1, "Invalid framebuffer store at %08h, size=%0d", address, access_size);
            end
            framebuffer_writes <= framebuffer_writes + 1;
        end
        if (TEST_CASE != 0 && load) begin
            case (address)
                32'hffff0018: begin
                    if (access_size != 3'b010 || fifo_empty)
                        $fatal(1, "Invalid KEY_DATA access, size=%0d count=%0d", access_size, fifo_used);
                    fifo_out <= (fifo_out + 1) % 16;
                    fifo_used <= fifo_used - 1;
                    pops <= pops + 1;
                end
                32'hffff001c: begin
                    if (access_size != 3'b010) $fatal(1, "Invalid KEY_STATUS access width");
                    status_reads <= status_reads + 1;
                    if (overflow) begin
                        overflow <= 0;
                        overflows_read <= overflows_read + 1;
                    end
                end
                32'hffff0010: tick_reads <= tick_reads + 1;
            endcase
        end
    end

    task automatic push_key(input [7:0] value);
        begin
            if (fifo_used == 16) overflow = 1;
            else begin
                fifo[fifo_in] = value;
                fifo_in = (fifo_in + 1) % 16;
                fifo_used = fifo_used + 1;
            end
        end
    endtask

    task automatic expect_label(input integer row, input [127:0] expected);
        integer index;
        begin
            for (index = 0; index < 16; index = index + 1)
                expect_cell(row, 32 + index, {8'h10, expected[127 - 8 * index -: 8]});
        end
    endtask

    task automatic capture_frame(input string filename);
        begin
            if (DEMO && $test$plusargs("capture_frames"))
                $writememh(filename, framebuffer);
        end
    endtask

    task automatic expect_cell(input integer row, col, input [15:0] expected);
        begin
            if (framebuffer[row * 80 + col] !== expected)
                $fatal(1, "Cell (%0d,%0d) expected %04h, got %04h",
                    row, col, expected, framebuffer[row * 80 + col]);
        end
    endtask

    // Use KEY_STATUS to find the start of the frame and the next TICK_MS
    // read to find its end. Both are transactions from the real CPU pipeline.
    task automatic advance_frame(input integer advance_ms);
        integer start_cycle, start_writes, previous_tick_reads, previous_status_reads;
        begin
            start_cycle = cycles;
            start_writes = framebuffer_writes;
            previous_status_reads = status_reads;
            tick = tick + advance_ms;
            wait (status_reads > previous_status_reads);
            previous_tick_reads = tick_reads;
            wait (tick_reads > previous_tick_reads);
            @(negedge cpu_clock);
            last_frame_cycles = cycles - start_cycle;
            last_frame_writes = framebuffer_writes - start_writes;
            if (last_frame_cycles > max_frame_cycles) max_frame_cycles = last_frame_cycles;
        end
    endtask

    task automatic direction(input [7:0] value);
        begin
            push_key(8'he0);
            push_key(value);
            advance_frame(17);
        end
    endtask

    task automatic tap(input [7:0] value);
        begin
            push_key(value);
            push_key(8'hf0);
            push_key(value);
            advance_frame(17);
        end
    endtask

    // Set up four near-full rows and a varied stack above them. Leave a
    // straight runway for an I piece at column 5.
    task automatic seed_four_rows;
        integer word_index, lane, row, col;
        reg [7:0] tile;
        reg [31:0] word_value;
        begin
            for (word_index = 0; word_index < 50; word_index = word_index + 1) begin
                word_value = 0;
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    row = (word_index * 4 + lane) / 10;
                    col = (word_index * 4 + lane) % 10;
                    if (row >= 16 && col != 5) tile = 2;
                    else if (row >= 4 && row < 16 && col < 4 && (row + col) % 4 != 0)
                        tile = 1 + (row + col) % 7;
                    else tile = 0;
                    word_value[lane * 8 +: 8] = tile;
                end
                dut.pipeline.memory_access.data_memory[word_index] = word_value;
            end
        end
    endtask

    initial begin
        #100;
        rst = 0;
        case (TEST_CASE)
            0: begin
                wait (led == 16'h8127 && seg_value == 32'h12345678);
                @(negedge cpu_clock);
                switches = 16'hc127;
                wait (led == 16'hc127 && seg_value == 1);
                wait (seg_value == 2);
                $display("PASS: diag_mmio SYS_ID, switches, SEG7 pattern and real TICK_MS");
            end
            1: begin
                wait (led == 16'h0202);
                expect_cell(0, 0, 16'h1041);
                expect_cell(0, 1, 16'h4043);
                expect_cell(0, 79, 16'h20db);
                expect_cell(1, 0, 16'h50db);
                expect_cell(29, 79, 16'h805a);
                if (framebuffer_writes != 1205 || seg_value !== 32'd0)
                    $fatal(1, "Unexpected VGA write count or SEG7 alias");
                $display("PASS: diag_vga pair order, isolated SH, cross-row and final cell");
            end
            2: begin
                wait (led == 16'h0203);
                @(negedge cpu_clock);
                push_key(8'he0); push_key(8'h6b);
                push_key(8'he0); push_key(8'hf0); push_key(8'h6b);
                wait (pops == 5 && framebuffer_writes == 1210);
                expect_cell(1, 0, 16'h1045); // E0
                expect_cell(1, 2, 16'h1036); // 6B
                expect_cell(1, 6, 16'h1046); // F0
                expect_cell(2, 2, 16'h1030);
                expect_cell(2, 3, 16'h1031); // logical LEFT=01
                expect_cell(2, 8, 16'h0020); // release produces no action
                @(negedge cpu_clock);
                repeat (17) push_key(8'he0);
                wait (pops == 21 && key_resync == 0);
                @(negedge cpu_clock);
                push_key(8'he0); push_key(8'h74);
                wait (pops == 23 && framebuffer[205] == 16'h1032);
                if (overflows_read != 1 || dut.pipeline.memory_access.data_memory[84] != 1)
                    $fatal(1, "Expected one read-clear overflow and recovery");
                $display("PASS: diag_key raw make/break, one pop per LW, overflow read-clear and resync");
            end
            3: begin
                wait (led == 16'h600d);
                wait (tick_reads >= 2);
                @(negedge cpu_clock);
                if (piece !== 1 || game_x !== 3 || game_mode !== 0)
                    $fatal(1, "Game startup mismatch piece=%h x=%h mode=%h", piece, game_x, game_mode);
                if (dut.pipeline.ie_ff !== 1'b0) $fatal(1, "Board key interrupts remain enabled");
                expect_cell(1, 6, 16'h1046); // FALLING BLOCKS
                expect_cell(4, 14, 16'h40db); // yellow O at the initial position
                expect_cell(14, 32, 16'h1050); // PLAYING
                expect_label(17, "LEFT/RIGHT MOVE ");
                expect_label(18, "UP ROTATE       ");
                expect_label(19, "DOWN SOFT DROP  ");
                expect_label(20, "SPACE HARD DROP ");
                expect_label(21, "P PAUSE/RESUME  ");
                expect_label(22, "R RESTART       ");
                expect_label(23, "ESC EXIT        ");
                capture_frame("demo-start.hex");
                direction(8'h6b);
                if (game_x !== 2 || last_frame_writes != 4) $fatal(1, "LEFT dirty update mismatch");
                expect_cell(4, 12, 16'h40db);
                push_key(8'he0); push_key(8'hf0); push_key(8'h6b);
                advance_frame(17);
                if (game_x !== 2 || last_frame_writes != 0) $fatal(1, "Break changed the pose");
                direction(8'h74);
                direction(8'h75);
                direction(8'h72);
                if (game_x !== 3 || rotation !== 1 || game_y !== 1) $fatal(1, "Other arrow keys failed");
                push_key(8'h4d);
                advance_frame(17);
                if (game_mode !== 1) $fatal(1, "Pause make failed");
                expect_cell(14, 33, 16'h1041); // PAUSED
                push_key(8'h4d);
                advance_frame(900);
                if (game_mode !== 1 || game_y !== 1) $fatal(1, "Pause repeat moved or resumed game");
                push_key(8'hf0); push_key(8'h4d);
                tap(8'h4d);
                if (game_mode !== 0 || game_y !== 1) $fatal(1, "Resume failed");

                tap(8'h2d);
                if (game_y !== 0) $fatal(1, "Restart did not reset the pose");
                repeat (4) direction(8'h6b);
                tap(8'h29);
                repeat (2) direction(8'h6b);
                tap(8'h29);
                tap(8'h29);
                repeat (2) direction(8'h74);
                tap(8'h29);
                repeat (4) direction(8'h74);
                tap(8'h29);
                clear_cycles = last_frame_cycles;
                clear_writes = last_frame_writes;
                if (score !== 300 || lines !== 2) $fatal(1, "Double clear mismatch score=%0d lines=%0d", score, lines);
                expect_cell(6, 39, 16'h1033); // score 0000000300
                expect_cell(9, 41, 16'h1032); // lines 0000000002
                expect_cell(23, 6, 16'h0020);
                capture_frame("demo-clear.hex");

                repeat (10) tap(8'h29);
                if (game_mode !== 2 || score !== 300) $fatal(1, "Expected top-out after ten pairs");
                expect_cell(14, 32, 16'h1047); // GAME OVER
                expect_cell(4, 14, 16'h40db);
                rng = 0;
                tap(8'h2d);
                if (game_mode !== 0 || score !== 0 || lines !== 0 || piece !== (DEMO ? 1 : 0))
                    $fatal(1, "Game-over restart or RNG selection failed");
                if (!DEMO) begin
                    direction(8'h75);
                    seed_four_rows();
                    advance_frame(17);
                    tap(8'h29);
                    four_clear_cycles = last_frame_cycles;
                    four_clear_writes = last_frame_writes;
                    if (lines !== 4 || score !== 800) $fatal(1, "Four-line fixture did not clear");
                    expect_cell(6, 39, 16'h1038);
                    expect_cell(9, 41, 16'h1034);
                    expect_cell(23, 6, 16'h40db); // surviving tile shifted down 4 rows
                end

                push_key(8'h76);
                tick = tick + 17;
                wait (game_mode == 3 && framebuffer[14 * 80 + 37] == 16'h1044);
                @(negedge cpu_clock);
                rst = 1;
                rng = DEMO ? 0 : 1;
                repeat (12) @(negedge cpu_clock);
                if (led !== 0) $fatal(1, "Reset did not clear the MMIO LED");
                rst = 0;
                wait (led == 16'h600d);
                if (game_mode !== 0 || score !== 0 || lines !== 0 || piece !== 1)
                    $fatal(1, "Reset did not start a clean game");
                expect_cell(23, 6, 16'h0020);
                if (max_frame_cycles >= 32000) $fatal(1, "Frame exceeded 16 ms at the proposed 2 MHz clock");
                if (DEMO)
                    $display("PASS: fixed-O demo, control labels, two-line clear, top-out, restart, exit and reset");
                else begin
                    $display("PASS: game firmware input, timing wrap, rendering, two/four lines, top-out, restart, exit and reset");
                    $display("METRIC: max_frame_cycles=%0d clear_cycles=%0d clear_writes=%0d four_clear_cycles=%0d four_clear_writes=%0d",
                        max_frame_cycles, clear_cycles, clear_writes, four_clear_cycles, four_clear_writes);
                end
            end
        endcase
        $finish;
    end

    initial begin
        #12000000;
        $fatal(1, "Firmware timeout case=%0d PC=%08h LED=%04h mode=%0d fifo=%0d pops=%0d status=%0d tick=%0d",
            TEST_CASE, pc, led, game_mode, fifo_used, pops, status_reads, tick_reads);
    end
endmodule

module test_diag_mmio;
    firmware_tb #(.TEST_CASE(0), .IMAGE("diag_mmio.mem")) testbench();
endmodule
module test_diag_vga;
    firmware_tb #(.TEST_CASE(1), .IMAGE("diag_vga.mem")) testbench();
endmodule
module test_diag_key;
    firmware_tb #(.TEST_CASE(2), .IMAGE("diag_key.mem")) testbench();
endmodule
module test_game_firmware;
    firmware_tb #(.TEST_CASE(3), .IMAGE("game.mem")) testbench();
endmodule
module test_game_demo;
    firmware_tb #(.TEST_CASE(3), .IMAGE("game_demo.mem"), .DEMO(1)) testbench();
endmodule
