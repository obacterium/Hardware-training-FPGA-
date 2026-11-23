`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// MMIO：外设寄存器组（Stage 1，对应 INTERFACE.md 第 3 节）
//   寄存器区 0xFFFF_0000 ~ 0xFFFF_0FFF（偏移见表），读为组合多路选择，
//   写在 cpu_clock 上升沿、Go && MemWrite && 地址命中时生效（与数据 RAM 同拍）。
//   Stage 1 寄存器：SYS_ID/SW_BTN(只读) LED/SEG7(只写) TICK_MS/CYCLES/RNG(只读)
//   KEY_DATA/KEY_STATUS 为 Stage 2 占位（键 FIFO 接入后替换）。
//////////////////////////////////////////////////////////////////////////////////

module MMIO(
    input         CLK,           // 100MHz 系统时钟
    input         cpu_clock,
    input         RST,           // 内核同步复位（rst_synced）
    input         Go,            // 运行使能（与 MEM 段 store 同拍门控）
    input         MemWrite,
    input  [31:0] Address,       // MEM 段访存地址（ALU 结果）
    input  [31:0] WriteData,
    input  [15:0] SW,
    input         BTNU,          // RST
    input         BTND,          // IR3
    input         BTNL,          // IR1
    input         BTNR,          // IR2
    input         BTNC,          // Go
    input  [15:0] Cycles,        // 内核周期计数器（total_cycles）
    output [31:0] ReadData,
    output [15:0] LED,           // LED 寄存器（交给顶层/内核做显示源选择）
    output [31:0] SEG7Reg        // 数码管寄存器（内核显示 mux 的 111 档）
    );

    wire        mmio_sel = (Address[31:16] == 16'hFFFF);
    wire [9:0]  offset   = Address[9:0];   // 字节偏移（case 标签用字节地址：0x00/0x04/0x08/...）

    // ---------- 只读寄存器 ----------
    wire [31:0] sys_id = 32'h43505556;                        // "CPU-V"
    wire [31:0] sw_btn = {11'b0, BTNC, BTNU, BTND, BTNL, BTNR, SW[15:0]};
    wire [31:0] cycles = {16'b0, Cycles};

    // ---------- 只写寄存器 ----------
    reg [15:0] led_reg;
    reg [31:0] seg7_reg;

    // ---------- 毫秒节拍计数器（100MHz / 100_000 = 1kHz，32 位可计约 49.7 天） ----------
    reg [16:0] tick_prescale;
    reg [31:0] tick_ms;
    always @(posedge CLK) begin
        if (RST) begin
            tick_prescale <= 17'b0;
            tick_ms       <= 32'b0;
        end else if (tick_prescale == 17'd99_999) begin
            tick_prescale <= 17'b0;
            tick_ms       <= tick_ms + 32'd1;
        end else begin
            tick_prescale <= tick_prescale + 17'd1;
        end
    end

    // ---------- 硬件 LFSR 随机数（x^32+x^22+x^2+x+1，每 CLK 推进，读为快照无副作用） ----------
    reg [31:0] lfsr = 32'hBEEFCAFE;
    always @(posedge CLK) begin
        if (RST) lfsr <= 32'hBEEFCAFE;
        else     lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end

    // ---------- 写译码（与 MEM 段 store 同时序） ----------
    always @(posedge cpu_clock) begin
        if (RST) begin
            led_reg  <= 16'b0;
            seg7_reg <= 32'b0;
        end else if (Go && MemWrite && mmio_sel) begin
            case (offset)
                8'h08: led_reg  <= WriteData[15:0];   // LED
                8'h0C: seg7_reg <= WriteData;         // SEG7
                default: ;
            endcase
        end
    end

    // ---------- 读多路选择（LB/LH 等字节访问 MMIO 的行为不定义，软件一律用 LW） ----------
    reg [31:0] read_mux;
    always @(*) begin
        case (offset)
            8'h00: read_mux = sys_id;               // SYS_ID
            8'h04: read_mux = sw_btn;               // SW_BTN
            8'h08: read_mux = 32'b0;                // LED（只写，读回 0）
            8'h0C: read_mux = 32'b0;                // SEG7（只写，读回 0）
            8'h10: read_mux = tick_ms;              // TICK_MS
            8'h14: read_mux = cycles;               // CYCLES
            8'h18: read_mux = 32'b0;                // KEY_DATA（Stage 2 接键 FIFO）
            8'h1C: read_mux = 32'h0000_0001;        // KEY_STATUS：空=1（Stage 2 前恒空）
            8'h20: read_mux = lfsr;                 // RNG
            8'h24: read_mux = 32'b0;                // INT_CTRL（预留）
            default: read_mux = 32'b0;
        endcase
    end

    assign ReadData = read_mux;
    assign LED      = led_reg;
    assign SEG7Reg  = seg7_reg;
endmodule
