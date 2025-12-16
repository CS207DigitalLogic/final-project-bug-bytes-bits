module Calculator_Core (
    input wire clk,
    input wire rst_n,

    // --- FSM 控制接口 ---
    input wire i_start_calc,        // 开始计算脉冲
    input wire [2:0] i_op_code,     // 操作码: 000=转置, 001=加法, 010=标量乘法, 011=乘法, etc.
    output reg o_calc_done,         // 计算完成信号

    // --- 操作数参数 (来自 FSM) ---
    // 操作数 1
    input wire [8:0]  i_op1_addr,   // 存储器基地址
    input wire [31:0] i_op1_m,      // 行数
    input wire [31:0] i_op1_n,      // 列数
    // 操作数 2
    input wire [8:0]  i_op2_addr,
    input wire [31:0] i_op2_m,      // 标量乘法下为标量
    input wire [31:0] i_op2_n,
    // 结果存放位置
    input wire [8:0]  i_res_addr,   

    // --- Storage 读接口 (直接连 Matrix_Storage 的读端口) ---
    output reg [8:0]  o_calc_req_addr, // 读地址请求
    input wire [31:0] i_storage_rdata, // 读回的数据

    // --- Storage 写接口 (连 Storage_Mux) ---
    output reg        o_calc_we,       // 写使能
    output reg [8:0]  o_calc_waddr,    // 写地址
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
    localparam S_INIT      = 1;
    localparam S_LOAD_A    = 2; // 加载矩阵 A
    localparam S_LOAD_B    = 3; // 加载矩阵 B
    localparam S_CALC      = 4; // 执行计算
    localparam S_WRITE     = 5; // 写回结果
    localparam S_DONE      = 6;

    reg [3:0] state, next_state;

    // =========================================================
    // 3. 计数器与辅助变量
    // =========================================================
    reg [7:0] cnt;          // 通用加载/写入计数器
    reg [7:0] next_cnt;
    reg [7:0] target_cnt;   // 目标总数 (m*n)
    reg [7:0] next_target_cnt;
    
    // 计算用的行列指针
    reg [3:0] row, col, k;   
    reg [31:0] acc_sum;      // 乘法累加器

    // 锁存维度，防止 FSM 在计算中途变化
    reg [31:0] m1, n1, m2, n2;
    reg [2:0] op;
    reg [31:0] res_m, res_n; // 结果的维度

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE;
            cnt<=0;
            target_cnt<=0;
            o_calc_done<=0;
            o_calc_we<=0;
            row<=0;
            col<=0;
            k<=0;
            acc_sum<=0;
        end
        else begin
            state<=next_state;
            cnt<=next_cnt;
            target_cnt<=next_target_cnt;
            o_calc_done<=0;
            o_calc_we<=0;
            case (state)
                S_IDLE: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    cnt<=0;
                    target_cnt<=0;
                end
                S_INIT: begin
                    m1<=i_op1_m;
                    n1<=i_op1_n;
                    m2<=i_op2_m;
                    n2<=i_op2_n;
                    op<=i_op_code;
                    if (i_op_code==3'd0) begin
                        res_m<=i_op1_n;
                        res_n<=i_op1_m;
                    end else if (i_op_code==3'd1 || i_op_code==3'd2) begin
                        res_m<=i_op1_m;
                        res_n<=i_op1_n;
                    end else begin
                        res_m<=i_op1_m;
                        res_n<=i_op2_n;
                    end
                end
                S_LOAD_A: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    if (cnt>0) begin
                        mem_a[cnt-1]<=i_storage_rdata;
                    end
                    if (cnt<target_cnt) begin
                        o_calc_req_addr<=i_op1_addr+cnt;
                    end
                    if (cnt==target_cnt)
                        mem_a[cnt-1]<=i_storage_rdata;
                end
                S_LOAD_B: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    if (cnt>0) begin
                        mem_b[cnt-1]<=i_storage_rdata;
                    end
                    if (cnt<target_cnt) begin
                        o_calc_req_addr<=i_op2_addr+cnt;
                    end
                    if (cnt==target_cnt)
                        mem_b[cnt-1]<=i_storage_rdata;
                end
                S_CALC: begin
                    case (op)
                        3'd0: begin
                            if (row<m1) begin
                                if (col<n1) begin
                                    mem_res[col*res_n+row]<=mem_a[row*n1+col];
                                    col<=col+1;
                                end else begin
                                    col<=0;
                                    row<=row+1;
                                end
                            end else begin
                            end
                        end
                        3'd1: begin
                            if (row<m1) begin
                                if (col<n1) begin
                                    mem_res[row*n1+col]<=mem_a[row*n1+col]+mem_b[row*n1+col];
                                    col<=col+1;
                                end else begin
                                    col<=0;
                                    row<=row+1;
                                end
                            end else begin
                            end
                        end
                        3'd2: begin
                            if (row<m1) begin
                                if (col<n1) begin
                                    mem_res[row*n1+col]<=mem_a[row*n1+col]*m2;
                                    col<=col+1;
                                end else begin
                                    col<=0;
                                    row<=row+1;
                                end
                            end else begin
                            end
                        end
                        3'd3: begin
                            if (row<m1) begin
                                if (col<n2) begin
                                    if (k<n1) begin
                                        acc_sum<=acc_sum+mem_a[row*n1+k]*mem_b[k*n2+col];
                                        k<=k+1;
                                    end else begin
                                        k<=0;
                                        mem_res[row*n2+col]<=acc_sum;
                                        acc_sum<=0;
                                        col<=col+1;
                                    end
                                end else begin
                                    col<=0;
                                    row<=row+1;
                                end
                            end else begin
                            end
                        end
                        default: begin //默认矩阵乘法
                            if (row<m1) begin
                                if (col<n2) begin
                                    if (k<n1) begin
                                        acc_sum<=acc_sum+mem_a[row*n1+k]*mem_b[k*n2+col];
                                        k<=k+1;
                                    end else begin
                                        k<=0;
                                        mem_res[row*n2+col]<=acc_sum;
                                        acc_sum<=0;
                                        col<=col+1;
                                    end
                                end else begin
                                    col<=0;
                                    row<=row+1;
                                end
                            end else begin
                            end
                        end
                    endcase
                end
                S_WRITE: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    if (cnt<target_cnt) begin
                        o_calc_we<=1;
                        o_calc_waddr<=i_res_addr+cnt;
                        o_calc_wdata<=mem_res[cnt];
                    end else begin
                    end
                end
                S_DONE: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    o_calc_done<=1;
                end
                default: begin
                    row<=0;
                    col<=0;
                    k<=0;
                    acc_sum<=0;
                    cnt<=0;
                    target_cnt<=0;
                end
            endcase
        end
    end

    always @(*) begin
        next_cnt=cnt;
        next_target_cnt=target_cnt;
        next_state=state;
        case(state)
            S_IDLE: begin
               if (i_start_calc) begin
                    next_state=S_INIT;
                    next_cnt=0;
                    next_target_cnt=0;
               end
               else begin
                    next_state=S_IDLE;
                    next_cnt=cnt;
                    next_target_cnt=target_cnt;
               end
            end
            S_INIT: begin
                next_cnt=0;
                next_target_cnt=i_op1_m*i_op1_n;
                next_state=S_LOAD_A;
            end
            S_LOAD_A: begin
                if (cnt>=target_cnt) begin
                    next_cnt=0;
                    if (op==3'd0 || op==3'd2) begin
                        next_target_cnt=res_m*res_n;
                        next_state=S_CALC;
                    end else begin
                        next_target_cnt=m2*n2;
                        next_state=S_LOAD_B;
                    end
                end else begin
                    next_target_cnt=target_cnt;
                    next_state=S_LOAD_A;
                    next_cnt=cnt+1;
                end
            end
            S_LOAD_B: begin
                if (cnt>=target_cnt) begin
                    next_cnt=0;
                    next_target_cnt=res_m*res_n;
                    next_state=S_CALC;
                end else begin
                    next_target_cnt=target_cnt;
                    next_state=S_LOAD_B;
                    next_cnt=cnt+1;
                end
            end
            S_CALC: begin
                if (row>=m1) begin
                    next_cnt=0;
                    next_target_cnt=target_cnt;
                    next_state=S_WRITE;
                end else begin
                    next_target_cnt=target_cnt;
                    next_state=S_CALC;
                    next_cnt=cnt;
                end
            end
            S_WRITE: begin
                if (cnt>=target_cnt) begin
                    next_cnt=0;
                    next_target_cnt=0;
                    next_state=S_DONE;
                end else begin
                    next_cnt=cnt+1;
                    next_target_cnt=target_cnt;
                    next_state=S_WRITE;
                end 
            end
            S_DONE: begin
                next_cnt=cnt;
                next_target_cnt=target_cnt;
                next_state=S_IDLE;
            end
            default: begin
                next_cnt=0;
                next_target_cnt=0;
                next_state=S_IDLE;
            end
        endcase
    end
endmodule