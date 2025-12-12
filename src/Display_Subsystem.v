module Display_Subsystem (
    input wire clk,
    input wire rst_n,

    // --- FSM 控制接口 ---
    input wire w_en_display,          // 启动展示
    // 0=单矩阵(Storage), 1=列表(Storage+Cache), 2=汇总, 3=缓存回显(Cache)
    input wire [1:0] w_disp_mode,

    // 矩阵参数
    input wire [31:0] w_disp_m,       // 矩阵行数
    input wire [31:0] w_disp_n,       // 矩阵列数
    input wire [7:0]  w_disp_base_addr, // 起始基地址
    input wire [1:0]  w_disp_total_cnt, // 该规格共有几个矩阵? (1或2)

    // 缓存回显时的选择 ID (1 或 2)
    input wire [1:0]  w_disp_selected_id,

    // 汇总模式接口
    input wire [7:0] i_system_total_count, // 系统总共有多少个矩阵
    input wire [2:0] i_system_types_count, // 系统总共有几种规格
    output reg [1:0] o_lut_idx_req,        // 告诉 FSM 我现在想看第几个规格的数据

    // --- Storage 交互接口 ---
    input wire [31:0] w_storage_rdata, // 读回的数据
    output reg [7:0]  w_disp_req_addr, // 读地址

    // --- UART 物理接口 ---
    output wire uart_tx_pin,          // 直接输出到 FPGA 串口引脚

    // --- 握手 ---
    output reg w_disp_done            // 完成标志
);

    // =========================================================================
    // 1. UART 发送模块例化与信号连接
    // =========================================================================
    
    // 内部连接信号
    reg [7:0]  w_disp_tx_data; // 状态机 -> UART 的数据
    reg        w_disp_tx_en;   // 状态机 -> UART 的发送脉冲
    wire       tx_busy;        // UART -> 状态机 的忙标志

    // 状态机使用的 "Ready" 信号 (不忙即为 Ready)
    wire w_tx_ready;
    assign w_tx_ready = ~tx_busy & ~w_disp_tx_en;

    // 例化 uart_tx
    uart_tx #(
        .CLK_FREQ(100_000_000), 
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(w_disp_tx_en),   // 连接发送使能
        .tx_data(w_disp_tx_data),  // 连接发送数据
        .tx(uart_tx_pin),          // 连接物理引脚
        .tx_busy(tx_busy)          // 连接忙信号
    );

    // =========================================================================
    // 内部缓存定义 (The Cache)
    // =========================================================================
    // 两个 5x5 矩阵，共 50 个数据
    // ID 1: index 0-24
    // ID 2: index 25-49
    reg [31:0] mat_cache [0:49]; 
    reg [31:0] r_cached_m, r_cached_n; // 缓存维度

    // =========================================================================
    // 2. 状态机定义
    // =========================================================================

    // ASCII 常量
    localparam ASC_0     = 8'd48;
    localparam ASC_SPACE = 8'd32;
    localparam ASC_CR    = 8'd13;
    localparam ASC_LF    = 8'd10;
    localparam ASC_STAR  = 8'd42; 

    // 状态定义 (ID分配)
    localparam S_IDLE         = 0;
    localparam S_INIT         = 1;
    
    // 列表模式 (Storage -> UART & Cache)
    localparam S_LIST_SHOW_ID = 2; 
    localparam S_LIST_ID_LF   = 3; 
    localparam S_LIST_REQ     = 4; 
    localparam S_LIST_WAIT    = 5; 
    localparam S_LIST_SEND    = 6; 
    localparam S_LIST_SEP     = 7; 
    
    // 缓存回显模式 (Cache -> UART)
    localparam S_CACHE_FETCH  = 8; 
    localparam S_CACHE_SEND   = 9; 
    localparam S_CACHE_SEP    = 10;
    
    // 汇总模式
    localparam S_SUM_TOTAL    = 16;
    localparam S_SUM_SP1      = 17;
    localparam S_SUM_CHECK    = 18;
    localparam S_SUM_M        = 19;
    localparam S_SUM_STAR1    = 20;
    localparam S_SUM_N        = 21;
    localparam S_SUM_STAR2    = 22;
    localparam S_SUM_CNT      = 23;
    localparam S_SUM_SP2      = 24;

    localparam S_DONE         = 30; 
    
    // 状态寄存器
    reg [5:0] state, next_state;

    // 数据寄存器
    reg [1:0] mat_idx;      
    reg [31:0] row_cnt, col_cnt;
    reg [1:0] tx_step;      
    reg [31:0] cache_rdata; 

    // =========================================================================
    // Stage 1: 状态寄存器更新 (Sequential Logic)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= S_IDLE;
        else 
            state <= next_state;
    end

    // =========================================================================
    // Stage 2: 次态逻辑判断 (Combinational Logic)
    // =========================================================================
    always @(*) begin
        next_state = state; // 默认保持

        case (state)
            S_IDLE: begin
                if (w_en_display) next_state = S_INIT;
            end

            S_INIT: begin
                if (w_disp_mode == 1)      next_state = S_LIST_SHOW_ID;
                else if (w_disp_mode == 2) next_state = S_SUM_TOTAL;
                else if (w_disp_mode == 3) next_state = S_CACHE_FETCH;
                else if (w_disp_mode == 0) next_state = S_LIST_REQ;
                else                       next_state = S_DONE; 
            end

            // --- 汇总模式 ---
            S_SUM_TOTAL: if (w_tx_ready) next_state = S_SUM_SP1;
            S_SUM_SP1:   if (w_tx_ready) next_state = S_SUM_CHECK;
            S_SUM_CHECK: begin
                if (o_lut_idx_req < i_system_types_count) next_state = S_SUM_M;
                else next_state = S_DONE;
            end
            S_SUM_M:     if (w_tx_ready) next_state = S_SUM_STAR1;
            S_SUM_STAR1: if (w_tx_ready) next_state = S_SUM_N;
            S_SUM_N:     if (w_tx_ready) next_state = S_SUM_STAR2;
            S_SUM_STAR2: if (w_tx_ready) next_state = S_SUM_CNT;
            S_SUM_CNT:   if (w_tx_ready) next_state = S_SUM_SP2;
            S_SUM_SP2:   if (w_tx_ready) next_state = S_SUM_CHECK; // 循环

            // --- 列表/单矩阵模式 ---
            S_LIST_SHOW_ID: if (w_tx_ready) next_state = S_LIST_ID_LF;
            S_LIST_ID_LF:   if (w_tx_ready) begin
                                if (tx_step == 0) next_state = S_LIST_ID_LF; // 还在发 \r
                                else next_state = S_LIST_REQ; // 发完 \n 去请求数据
                            end
            S_LIST_REQ:     next_state = S_LIST_WAIT;
            S_LIST_WAIT:    next_state = S_LIST_SEND;
            S_LIST_SEND:    if (w_tx_ready) next_state = S_LIST_SEP;
            S_LIST_SEP:     if (w_tx_ready) begin
                                if (col_cnt == w_disp_n - 1) begin
                                    // 行末
                                    if (tx_step == 0) next_state = S_LIST_SEP; // 发 \r
                                    else begin
                                        // 发完 \n
                                        if (row_cnt == w_disp_m - 1) begin
                                            // 矩阵结束
                                            if (mat_idx + 1 < w_disp_total_cnt) next_state = S_LIST_SHOW_ID;
                                            else next_state = S_DONE;
                                        end else begin
                                            next_state = S_LIST_REQ; // 下一行
                                        end
                                    end
                                end else begin
                                    // 列中
                                    next_state = S_LIST_REQ; // 下一列
                                end
                            end

            // --- 缓存模式 ---
            S_CACHE_FETCH: next_state = S_CACHE_SEND;
            S_CACHE_SEND:  if (w_tx_ready) next_state = S_CACHE_SEP;
            S_CACHE_SEP:   if (w_tx_ready) begin
                                if (col_cnt == r_cached_n - 1) begin
                                    if (tx_step == 0) next_state = S_CACHE_SEP;
                                    else begin
                                        if (row_cnt == r_cached_m - 1) next_state = S_DONE;
                                        else next_state = S_CACHE_FETCH;
                                    end
                                end else begin
                                    next_state = S_CACHE_FETCH;
                                end
                           end

            S_DONE: begin
                if (!w_en_display) 
                    next_state = S_IDLE; // 只有看到 FSM 撤销了使能，才回空闲
                else 
                    next_state = S_DONE; // 否则在这里等待，维持 done 信号
            end
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // Stage 3: 数据输出与寄存器更新 (Sequential Logic)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_disp_done <= 0;
            w_disp_tx_en <= 0;
            w_disp_req_addr <= 0;
            w_disp_tx_data <= 0;
            mat_idx <= 0; row_cnt <= 0; col_cnt <= 0;
            tx_step <= 0;
            r_cached_m <= 0; r_cached_n <= 0;
            o_lut_idx_req <= 0;
        end 
        else begin
            // 脉冲默认复位
            w_disp_done <= 0;
            w_disp_tx_en <= 0;

            case (state)
                // S_IDLE 无动作，保持默认

                S_INIT: begin
                    mat_idx <= 0; row_cnt <= 0; col_cnt <= 0; tx_step <= 0;
                    
                    if (w_disp_mode == 1) begin 
                        r_cached_m <= w_disp_m; r_cached_n <= w_disp_n;
                    end
                    else if (w_disp_mode == 2) begin 
                        o_lut_idx_req <= 0; 
                    end
                    else if (w_disp_mode == 3) begin 
                        if (w_disp_selected_id == 2) mat_idx <= 1; else mat_idx <= 0;
                    end
                    else if (w_disp_mode == 0) begin
                        mat_idx <= 0; 
                    end
                end

                // --- 汇总模式 ---
                S_SUM_TOTAL: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= i_system_total_count[7:0] + ASC_0;
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_SP1: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_SPACE;
                        w_disp_tx_en <= 1;
                    end
                end
                // S_SUM_CHECK 纯跳转，无输出动作
                S_SUM_M: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_disp_m[7:0] + ASC_0; 
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_STAR1: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_STAR; 
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_N: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_disp_n[7:0] + ASC_0; 
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_STAR2: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_STAR; 
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_CNT: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= {6'b0, w_disp_total_cnt} + ASC_0; 
                        w_disp_tx_en <= 1;
                    end
                end
                S_SUM_SP2: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_SPACE; 
                        w_disp_tx_en <= 1;
                        o_lut_idx_req <= o_lut_idx_req + 1; // 准备查下一个
                    end
                end

                // --- 列表/单矩阵模式 ---
                S_LIST_SHOW_ID: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= (mat_idx + 1) + ASC_0; 
                        w_disp_tx_en <= 1;
                        tx_step <= 0;
                    end
                end
                S_LIST_ID_LF: begin
                    if (w_tx_ready) begin
                        if (tx_step == 0) begin
                            w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1;
                        end else begin
                            w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1;
                            row_cnt <= 0; col_cnt <= 0;
                        end
                    end
                end
                S_LIST_REQ: begin
                    w_disp_req_addr <= w_disp_base_addr + 
                                       (mat_idx * w_disp_m * w_disp_n) + 
                                       (row_cnt * w_disp_n) + 
                                       col_cnt;
                end
                // S_LIST_WAIT 无动作
                S_LIST_SEND: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_storage_rdata[7:0] + ASC_0;
                        w_disp_tx_en <= 1;
                        mat_cache[(mat_idx * 25) + (row_cnt * w_disp_n) + col_cnt] <= w_storage_rdata;
                        tx_step <= 0;
                    end
                end
                S_LIST_SEP: begin
                    if (w_tx_ready) begin
                        if (col_cnt == w_disp_n - 1) begin
                            if (tx_step == 0) begin
                                w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1;
                            end else begin
                                w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1;
                                col_cnt <= 0;
                                if (row_cnt == w_disp_m - 1) begin
                                    mat_idx <= mat_idx + 1;
                                end else begin
                                    row_cnt <= row_cnt + 1;
                                end
                            end
                        end else begin
                            w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1;
                            col_cnt <= col_cnt + 1;
                        end
                    end
                end

                // --- 缓存模式 ---
                S_CACHE_FETCH: begin
                    cache_rdata <= mat_cache[(mat_idx * 25) + (row_cnt * r_cached_n) + col_cnt];
                end
                S_CACHE_SEND: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= cache_rdata[7:0] + ASC_0; 
                        w_disp_tx_en <= 1;
                        tx_step <= 0;
                    end
                end
                S_CACHE_SEP: begin
                    if (w_tx_ready) begin
                        if (col_cnt == r_cached_n - 1) begin
                            if (tx_step == 0) begin
                                w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1;
                            end else begin
                                w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1;
                                col_cnt <= 0;
                                if (row_cnt != r_cached_m - 1) begin
                                    row_cnt <= row_cnt + 1;
                                end
                            end
                        end else begin
                            w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1;
                            col_cnt <= col_cnt + 1;
                        end
                    end
                end

                S_DONE: begin
                    w_disp_done <= 1;
                end
            endcase
        end
    end

endmodule