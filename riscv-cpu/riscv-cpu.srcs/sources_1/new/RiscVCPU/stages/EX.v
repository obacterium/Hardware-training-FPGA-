`timescale 1ns / 1ps

module EX(
    input  [31:0] PC,
    input  [31:0] RS1,
    input  [31:0] RS2,
    input  [31:0] ImmI,
    input  [31:0] ImmB,
    input  [31:0] ImmJ,
    input  [31:0] IR,
    input  [31:0] EPC,
    input  [3:0]  ALU_OP,
    input         ALU_SRC,
    output [31:0] ALUResult,
    output [31:0] Result2,
    output [31:0] StoreData,
    output        Equal,
    output        BranchTaken,
    output        RedirectValid,
    output [31:0] RedirectPC,
    output        EcallDisplay,
    output        EcallHalt
    );

    // 地址立即数：存数指令(SW/SB/SH)必须用 S 型立即数 {IR[31:25],IR[11:7]}，
    // 其余用 I 型立即数（此前存数误用 I 型 → sw X,0(sp) 实际写 sp+rs2 字段，现场保护全乱）
    wire [31:0] ImmS = {{20{IR[31]}}, IR[31:25], IR[11:7]};
    wire        is_store = (IR[6:2] == 5'b01000);
    wire [31:0] operand_b = ALU_SRC ? (is_store ? ImmS : ImmI) : RS2;
    wire greater_equal_unused, less_unused, geu_unused;

    ALU alu (
        .X(RS1), .Y(operand_b), .AluOP(ALU_OP), .Result(ALUResult),
        .Result2(Result2), .Equal(Equal),
        .GreaterEqual(greater_equal_unused),
        .GreaterEqualUnsigned(geu_unused),
        .Less(less_unused)
    );

    // ---------- 指令识别（EX 段直接看 IR，不依赖流水信号） ----------
    wire [2:0] funct3   = IR[14:12];
    wire       is_branch = IR[6:2] == 5'b11000;
    wire       is_jal    = IR[6:0] == 7'b1101111;
    wire       is_jalr   = IR[6:2] == 5'b11001;
    wire       is_ecall  = (IR[6:2] == 5'b11100) && (funct3 == 3'b000) && ~IR[21];
    wire       is_uret   = (IR[6:2] == 5'b11100) && (funct3 == 3'b000) &&  IR[21];

    wire less_signed   = $signed(RS1) <  $signed(RS2);
    wire ge_signed     = $signed(RS1) >= $signed(RS2);
    wire less_unsigned = RS1 <  RS2;
    wire ge_unsigned   = RS1 >= RS2;

    assign StoreData = RS2;

    // 六种条件分支（BEQ/BNE/BLT/BGE/BLTU/BGEU）
    assign BranchTaken = is_branch && (
        (funct3 == 3'b000 &&  Equal) ||
        (funct3 == 3'b001 && ~Equal) ||
        (funct3 == 3'b100 &&  less_signed) ||
        (funct3 == 3'b101 &&  ge_signed) ||
        (funct3 == 3'b110 &&  less_unsigned) ||
        (funct3 == 3'b111 &&  ge_unsigned));

    // 重定向：分支 / JAL / JALR / URET（中断返回：EPC → PC）
    assign RedirectValid = is_jalr | is_jal | BranchTaken | is_uret;
    assign RedirectPC = is_uret ? EPC :
                        is_jalr ? ((RS1 + ImmI) & 32'hffff_fffe) :
                        is_jal  ? (PC + ImmJ) : (PC + ImmB);

    // ecall：a7==34 → 显示 a0（不阻塞）；否则 → 停机等待 Go 按键
    assign EcallDisplay = is_ecall && (RS1 == 32'd34);
    assign EcallHalt    = is_ecall && (RS1 != 32'd34);
endmodule
