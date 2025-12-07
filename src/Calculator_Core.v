module Calculator_Core (
    input wire clk,
    input wire rst_n,

    // --- FSM 控制接口 ---
    input wire i_start_calc,        // 开始计算脉冲
    input wire [2:0] i_op_code,     // 操作码: 000=转置, 001=加法, 010=乘法, etc.
    output reg o_calc_done,         // 计算完成信号

    // --- 操作数参数 (来自 FSM) ---
    // 操作数 1
    input wire [7:0]  i_op1_addr,   // 存储器基地址
    input wire [31:0] i_op1_m,      // 行数
    input wire [31:0] i_op1_n,      // 列数
    // 操作数 2
    input wire [7:0]  i_op2_addr,
    input wire [31:0] i_op2_m,
    input wire [31:0] i_op2_n,
    // 结果存放位置
    input wire [7:0]  i_res_addr,   

    // --- Storage 读接口 (直接连 Matrix_Storage 的读端口) ---
    output reg [7:0]  o_calc_req_addr, // 读地址请求
    input wire [31:0] i_storage_rdata, // 读回的数据

    // --- Storage 写接口 (连 Storage_Mux) ---
    output reg        o_calc_we,       // 写使能
    output reg [7:0]  o_calc_waddr,    // 写地址
    output reg [31:0] o_calc_wdata     // 写数据
);

    // =========================================================
    // 1. 内部缓存 (Cache) - 最大支持 5x5 = 25
    // =========================================================
    reg [31:0] mem_a   [0:24];
    reg [31:0] mem_b   [0:24];
    reg [31:0] mem_res [0:24];

    // =========================================================
    // 2. 状态机定义
    // =========================================================
    localparam S_IDLE      = 0;
    localparam S_LOAD_A    = 1; // 加载矩阵 A
    localparam S_LOAD_B    = 2; // 加载矩阵 B
    localparam S_CALC      = 3; // 执行计算
    localparam S_WRITE     = 4; // 写回结果
    localparam S_DONE      = 5;

    reg [3:0] state;

    // =========================================================
    // 3. 计数器与辅助变量
    // =========================================================
    reg [7:0]  cnt;          // 通用加载/写入计数器
    reg [7:0]  target_cnt;   // 目标总数 (m*n)
    
    // 计算用的行列指针
    reg [3:0] row, col, k;   
    reg [31:0] acc_sum;      // 乘法累加器

    // 锁存维度，防止 FSM 在计算中途变化
    reg [31:0] m1, n1, m2, n2;
    reg [31:0] res_m, res_n; // 结果的维度

endmodule