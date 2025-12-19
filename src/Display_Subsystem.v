`timescale 1ns / 1ps

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
    input wire [8:0]  w_disp_base_addr, // 起始基地址
    input wire [1:0]  w_disp_total_cnt, // 该规格共有几个矩阵?

    // 缓存回显时的选择 ID (1 或 2)
    input wire [1:0]  w_disp_selected_id,

    // 汇总模式接口
    input wire [7:0] i_system_total_count, // 系统总共有多少个矩阵
    input wire [4:0] i_system_types_count, // 系统总共有几种规格
    output reg [4:0] o_lut_idx_req,        // 告诉 FSM 我现在想看第几个规格的数据

    // --- Storage 交互接口 ---
    input wire [31:0] w_storage_rdata, // 读回的数据
    output reg [8:0]  w_disp_req_addr, // 读地址

    // --- UART 物理接口 ---
    output wire uart_tx_pin,          // 直接输出到 FPGA 串口引脚

    // --- 握手 ---
    output reg w_disp_done            // 完成标志
);

    // =========================================================================
    // 1. UART 发送模块例化
    // =========================================================================
    reg [7:0]  w_disp_tx_data;
    reg        w_disp_tx_en;
    wire       tx_busy;
    wire       w_tx_ready;
    assign w_tx_ready = ~tx_busy & ~w_disp_tx_en;

    uart_tx #(
        .CLK_FREQ(25_000_000), 
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(w_disp_tx_en),
        .tx_data(w_disp_tx_data),
        .tx(uart_tx_pin),
        .tx_busy(tx_busy)
    );

    // =========================================================================
    // 内部缓存 (Cache)
    // =========================================================================
    reg [31:0] mat_cache [0:49];
    reg [31:0] r_cached_m, r_cached_n;

    // =========================================================================
    // 2. 状态机定义
    // =========================================================================
    localparam ASC_SPACE = 8'd32;
    localparam ASC_CR    = 8'd13;
    localparam ASC_LF    = 8'd10;
    localparam ASC_STAR  = 8'd42; 

    // Main States
    localparam S_IDLE         = 0;
    localparam S_INIT         = 1;
    
    // List / Matrix States
    localparam S_LIST_SHOW_ID = 2; 
    localparam S_LIST_ID_LF   = 3;
    localparam S_LIST_REQ     = 4; 
    localparam S_LIST_WAIT    = 5;
    localparam S_LIST_SEND    = 6; 
    localparam S_LIST_SEP     = 7;
    
    // Cache States
    localparam S_CACHE_FETCH  = 8; 
    localparam S_CACHE_SEND   = 9;
    localparam S_CACHE_SEP    = 10;
    
    // Summary States
    localparam S_SUM_TOTAL    = 16;
    localparam S_SUM_SP1      = 17;
    localparam S_SUM_CHECK    = 18;
    localparam S_SUM_M        = 19;
    localparam S_SUM_STAR1    = 20;
    localparam S_SUM_N        = 21;
    localparam S_SUM_STAR2    = 22;
    localparam S_SUM_CNT      = 23;
    localparam S_SUM_SP2      = 24;
    localparam S_SUM_DONE_CR  = 25; // 发送回车 \r
    localparam S_SUM_DONE_LF  = 26; // 发送换行 \n

    localparam S_SCALAR_PREP    = 30; // 标量准备
    localparam S_SCALAR_DONE_CR = 31; // 标量回车
    localparam S_SCALAR_DONE_LF = 32; // 标量换行
    
    // Decimal Conversion States (New Engine)
    localparam S_CONV_START   = 40;
    localparam S_CONV_ITER    = 41;
    localparam S_TX_DIGIT     = 42;

    localparam S_DONE         = 50;

    reg [5:0] state, next_state;
    reg [1:0] mat_idx;
    reg [31:0] row_cnt, col_cnt;
    reg [1:0] tx_step;      
    reg [31:0] cache_rdata;

    // Decimal Conversion Registers
    reg [31:0] r_val_to_show;      // 要显示的数值
    reg [5:0]  r_return_state;     // 显示完后回哪去
    reg [7:0]  r_dec_buf [0:9];    // 存放十进制位 (最大32位整数是10位数)
    reg [3:0]  r_buf_ptr;          // buffer 指针
    reg [31:0] r_temp_val;         // 计算中间值

    // =========================================================================
    // Stage 1: State Update
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else state <= next_state;
    end

    // =========================================================================
    // Stage 2: Next State Logic
    // =========================================================================
    always @(*) begin
        next_state = state; // Default hold

        case (state)
            S_IDLE: if (w_en_display) next_state = S_INIT;

            S_INIT: begin
                if (w_disp_mode == 1)      next_state = S_LIST_SHOW_ID;
                else if (w_disp_mode == 2) next_state = S_SUM_TOTAL;
                else if (w_disp_mode == 3) next_state = S_CACHE_FETCH;
                else if (w_disp_mode == 0) next_state = S_LIST_REQ;
                else if (w_disp_mode == 4) next_state = S_SCALAR_PREP;
                else                       next_state = S_DONE;
            end

            // --- Summary Mode ---
            // Replace direct TX states with calls to conversion if needed
            S_SUM_TOTAL: next_state = S_CONV_START; // Send Total Count
            S_SUM_SP1:   if (w_tx_ready) next_state = S_SUM_CHECK;
            
            S_SUM_CHECK: begin
                if (o_lut_idx_req < i_system_types_count) next_state = S_SUM_M;
                else next_state = S_SUM_DONE_CR;
            end
            
            S_SUM_M:     next_state = S_CONV_START; // Send M
            S_SUM_STAR1: if (w_tx_ready) next_state = S_SUM_N;
            S_SUM_N:     next_state = S_CONV_START; // Send N
            S_SUM_STAR2: if (w_tx_ready) next_state = S_SUM_CNT;
            S_SUM_CNT:   next_state = S_CONV_START; // Send Count
            S_SUM_SP2:   if (w_tx_ready) next_state = S_SUM_CHECK;

            S_SUM_DONE_CR: if (w_tx_ready) next_state = S_SUM_DONE_LF;
            S_SUM_DONE_LF: if (w_tx_ready) next_state = S_DONE;

            // --- List/Single Matrix Mode ---
            S_LIST_SHOW_ID: next_state = S_CONV_START; // Send ID
            
            S_LIST_ID_LF:   if (w_tx_ready) begin
                                if (tx_step == 0) next_state = S_LIST_ID_LF;
                                else next_state = S_LIST_REQ;
                            end
            S_LIST_REQ:     next_state = S_LIST_WAIT;
            S_LIST_WAIT:    next_state = S_LIST_SEND;
            
            S_LIST_SEND:    next_state = S_CONV_START; // Send Matrix Data (Decimal!)
            
            S_LIST_SEP:     if (w_tx_ready) begin
                                if (col_cnt == w_disp_n - 1) begin
                                    if (tx_step == 0) next_state = S_LIST_SEP;
                                    else begin
                                        if (row_cnt == w_disp_m - 1) begin
                                            if (mat_idx + 1 < w_disp_total_cnt) next_state = S_LIST_SHOW_ID;
                                            else next_state = S_DONE;
                                        end else next_state = S_LIST_REQ;
                                    end
                                end else next_state = S_LIST_REQ;
                            end

            // --- Cache Mode ---
            S_CACHE_FETCH: next_state = S_CACHE_SEND;
            S_CACHE_SEND:  next_state = S_CONV_START; // Send Cached Data (Decimal!)
            
            S_CACHE_SEP:   if (w_tx_ready) begin
                                if (col_cnt == r_cached_n - 1) begin
                                    if (tx_step == 0) next_state = S_CACHE_SEP;
                                    else begin
                                        if (row_cnt == r_cached_m - 1) next_state = S_DONE;
                                        else next_state = S_CACHE_FETCH;
                                    end
                                end else next_state = S_CACHE_FETCH;
                           end

            S_SCALAR_PREP:    next_state = S_CONV_START; // 去转十进制
            
            S_SCALAR_DONE_CR: if (w_tx_ready) next_state = S_SCALAR_DONE_LF;
            S_SCALAR_DONE_LF: if (w_tx_ready) next_state = S_DONE;

            // --- Decimal Conversion Engine ---
            S_CONV_START: next_state = S_CONV_ITER;
            S_CONV_ITER:  begin
                // Simple iterative logic handled in sequential block
                // If done (temp_val < 10), go to TX
                if (r_temp_val < 10) next_state = S_TX_DIGIT;
                else next_state = S_CONV_ITER;
            end
            S_TX_DIGIT:   begin
                if (w_tx_ready) begin
                    // Buffer empty?
                    if (r_buf_ptr == 0) next_state = r_return_state; // Return to caller
                    else next_state = S_TX_DIGIT;
                end
            end

            // --- Done ---
            S_DONE: begin
                // Handshake fix: wait for Enable to drop
                if (!w_en_display) next_state = S_IDLE;
                else next_state = S_DONE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // Stage 3: Outputs & Data Path
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_disp_done <= 0; w_disp_tx_en <= 0; w_disp_req_addr <= 0;
            w_disp_tx_data <= 0;
            mat_idx <= 0; row_cnt <= 0; col_cnt <= 0; tx_step <= 0;
            r_cached_m <= 0; r_cached_n <= 0; o_lut_idx_req <= 0;
            r_buf_ptr <= 0; r_temp_val <= 0; r_val_to_show <= 0; r_return_state <= S_IDLE;
        end 
        else begin
            w_disp_done <= 0;
            w_disp_tx_en <= 0;

            case (state)
                S_INIT: begin
                    mat_idx <= 0; row_cnt <= 0; col_cnt <= 0; tx_step <= 0;
                    
                    // 【修复核心】：Mode 0 (单矩阵) 和 Mode 1 (列表) 都会写缓存，必须同步更新缓存维度！
                    if (w_disp_mode == 1 || w_disp_mode == 0) begin 
                        r_cached_m <= w_disp_m; 
                        r_cached_n <= w_disp_n; 
                    end
                    
                    if (w_disp_mode == 1) begin 
                        // r_cached_m/n updated above
                    end
                    else if (w_disp_mode == 2) o_lut_idx_req <= 0;
                    else if (w_disp_mode == 3) begin 
                        if (w_disp_selected_id == 2) mat_idx <= 1; else mat_idx <= 0;
                    end
                    else if (w_disp_mode == 0) begin
                        mat_idx <= 0;
                    end
                end

                // --- Summary Data Prep ---
                S_SUM_TOTAL: begin
                    r_val_to_show <= i_system_total_count;
                    r_return_state <= S_SUM_SP1;
                end
                S_SUM_SP1: if (w_tx_ready) begin w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1; end
                
                S_SUM_M: begin
                    r_val_to_show <= w_disp_m;
                    r_return_state <= S_SUM_STAR1;
                end
                S_SUM_STAR1: if (w_tx_ready) begin w_disp_tx_data <= ASC_STAR; w_disp_tx_en <= 1; end
                
                S_SUM_N: begin
                    r_val_to_show <= w_disp_n;
                    r_return_state <= S_SUM_STAR2;
                end
                S_SUM_STAR2: if (w_tx_ready) begin w_disp_tx_data <= ASC_STAR; w_disp_tx_en <= 1; end
                
                S_SUM_CNT: begin
                    r_val_to_show <= w_disp_total_cnt;
                    r_return_state <= S_SUM_SP2;
                end
                S_SUM_SP2: if (w_tx_ready) begin 
                    w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1; 
                    o_lut_idx_req <= o_lut_idx_req + 1; 
                end

                S_SUM_DONE_CR: if (w_tx_ready) begin
                    w_disp_tx_data <= ASC_CR; // 发送 \r (13)
                    w_disp_tx_en <= 1;
                end

                S_SUM_DONE_LF: if (w_tx_ready) begin
                    w_disp_tx_data <= ASC_LF; // 发送 \n (10)
                    w_disp_tx_en <= 1;
                end

                // --- List ID Prep ---
                S_LIST_SHOW_ID: begin
                    r_val_to_show <= (mat_idx + 1);
                    r_return_state <= S_LIST_ID_LF;
                    tx_step <= 0;
                end
                S_LIST_ID_LF: if (w_tx_ready) begin
                    if (tx_step == 0) begin w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1; end 
                    else begin w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1; row_cnt <= 0; col_cnt <= 0; end
                end

                // --- Matrix Data Prep ---
                S_LIST_REQ: w_disp_req_addr <= w_disp_base_addr + (mat_idx * w_disp_m * w_disp_n) + (row_cnt * w_disp_n) + col_cnt;
                
                S_LIST_SEND: begin
                    // Store to cache
                    mat_cache[(mat_idx * 25) + (row_cnt * w_disp_n) + col_cnt] <= w_storage_rdata;
                    // Prepare to send Decimal
                    r_val_to_show <= w_storage_rdata;
                    r_return_state <= S_LIST_SEP;
                    tx_step <= 0;
                end

                S_LIST_SEP: if (w_tx_ready) begin
                    if (col_cnt == w_disp_n - 1) begin
                        if (tx_step == 0) begin w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1; end 
                        else begin 
                            w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1; 
                            col_cnt <= 0; 
                            if (row_cnt == w_disp_m - 1) mat_idx <= mat_idx + 1; else row_cnt <= row_cnt + 1;
                        end
                    end else begin
                        w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1; col_cnt <= col_cnt + 1;
                    end
                end

                // --- Cache Data Prep ---
                S_CACHE_FETCH: cache_rdata <= mat_cache[(mat_idx * 25) + (row_cnt * r_cached_n) + col_cnt];
                
                S_CACHE_SEND: begin
                    r_val_to_show <= cache_rdata;
                    r_return_state <= S_CACHE_SEP;
                    tx_step <= 0;
                end
                
                S_CACHE_SEP: if (w_tx_ready) begin
                    if (col_cnt == r_cached_n - 1) begin
                        if (tx_step == 0) begin w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1; end 
                        else begin 
                            w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1; 
                            col_cnt <= 0; 
                            if (row_cnt != r_cached_m - 1) row_cnt <= row_cnt + 1;
                        end
                    end else begin
                        w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1; col_cnt <= col_cnt + 1;
                    end
                end

                S_SCALAR_PREP: begin
                    r_val_to_show <= w_disp_m;        // 复用 w_disp_m 传递标量
                    r_return_state <= S_SCALAR_DONE_CR; // 打印完数字后去打印回车
                    r_buf_ptr <= 0;
                end

                S_SCALAR_DONE_CR: if (w_tx_ready) begin
                    w_disp_tx_data <= ASC_CR;
                    w_disp_tx_en <= 1;
                end

                S_SCALAR_DONE_LF: if (w_tx_ready) begin
                    w_disp_tx_data <= ASC_LF;
                    w_disp_tx_en <= 1;
                end

                // =============================================================
                // Decimal Conversion Engine
                // =============================================================
                S_CONV_START: begin
                    r_temp_val <= r_val_to_show;
                    r_buf_ptr <= 0; // Starts from 0
                end

                S_CONV_ITER: begin
                    // Iterative extraction (Binary to BCD digits)
                    if (r_temp_val >= 10) begin
                        r_dec_buf[r_buf_ptr] <= (r_temp_val % 10) + 8'd48;
                        r_temp_val <= r_temp_val / 10;
                        r_buf_ptr <= r_buf_ptr + 1;
                    end else begin
                        r_dec_buf[r_buf_ptr] <= r_temp_val + 8'd48;
                        // r_buf_ptr now points to the most significant digit
                    end
                end

                S_TX_DIGIT: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= r_dec_buf[r_buf_ptr];
                        w_disp_tx_en <= 1;
                        if (r_buf_ptr > 0) r_buf_ptr <= r_buf_ptr - 1;
                    end
                end

                S_DONE: w_disp_done <= 1;
            endcase
        end
    end

endmodule