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
    // --- Storage 交互接口 ---
    input wire [31:0] w_storage_rdata, // 读回的数据
    output reg [7:0]  w_disp_req_addr, // 读地址

    // --- UART 物理接口 (修改处) ---
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
    assign w_tx_ready = ~tx_busy;

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
    // 2. 状态机逻辑 (保持原逻辑不变)
    // =========================================================================

    // ASCII 常量
    localparam ASC_0     = 8'd48;
    localparam ASC_SPACE = 8'd32;
    localparam ASC_CR    = 8'd13;
    localparam ASC_LF    = 8'd10;

    // 状态定义
    localparam S_IDLE         = 0;
    localparam S_INIT         = 1;
    
    // 列表模式 (Storage -> UART & Cache)
    localparam S_LIST_SHOW_ID = 2; 
    localparam S_LIST_ID_LF   = 3; 
    localparam S_LIST_REQ     = 4; 
    localparam S_LIST_WAIT    = 5; 
    localparam S_LIST_SEND    = 6; // 在这里写入缓存！
    localparam S_LIST_SEP     = 7; 
    
    // [新增] 缓存回显模式 (Cache -> UART)
    localparam S_CACHE_FETCH  = 8; // 从 Cache 拿数据
    localparam S_CACHE_SEND   = 9; // 发送数据
    localparam S_CACHE_SEP    = 10;
    
    localparam S_DONE         = 15;
    
    reg [3:0] state;
    reg [1:0] mat_idx;      
    reg [31:0] row_cnt, col_cnt;
    reg [1:0] tx_step;      
    reg [31:0] cache_rdata; // 从缓存读出的临时数据

    // --------------------------------------------------------
    // 逻辑实现
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            w_disp_done <= 0;
            w_disp_tx_en <= 0;
            w_disp_req_addr <= 0;
            w_disp_tx_data <= 0;
            mat_idx <= 0; row_cnt <= 0; col_cnt <= 0;
            tx_step <= 0;
            r_cached_m <= 0; r_cached_n <= 0;
        end 
        else begin
            // 脉冲复位
            w_disp_done <= 0;
            w_disp_tx_en <= 0;

            case (state)
                S_IDLE: begin
                    if (w_en_display) begin
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    mat_idx <= 0; row_cnt <= 0; col_cnt <= 0; tx_step <= 0;
                    
                    if (w_disp_mode == 1) begin // 列表模式
                        state <= S_LIST_SHOW_ID;
                        r_cached_m <= w_disp_m; r_cached_n <= w_disp_n;
                    end
                    else if (w_disp_mode == 2) begin // 汇总模式
                        state <= S_SUM_TOTAL;
                        // o_lut_idx_req <= 0; // (注意：如需汇总模式，请确保端口和逻辑完整)
                    end
                    else if (w_disp_mode == 3) begin // 缓存回显
                        state <= S_CACHE_FETCH;
                        if (w_disp_selected_id == 2) mat_idx <= 1; else mat_idx <= 0;
                    end
                    // Mode 0: 单矩阵显示 
                    else if (w_disp_mode == 0) begin
                        // 直接跳过 ID 显示，复用请求数据的逻辑
                        state <= S_LIST_REQ;
                        mat_idx <= 0; // 默认第0个（FSM会保证 base_addr 是正确的起始地址）
                    end
                    else state <= S_DONE; 
                end

                // ============================================================
                // 汇总模式逻辑 
                // ============================================================
                // 1. 发送总数 
                S_SUM_TOTAL: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= i_system_total_count[7:0] + ASC_0;
                        w_disp_tx_en <= 1;
                        state <= S_SUM_SP1;
                    end
                end
                
                // 2. 发送空格 " "
                S_SUM_SP1: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_SPACE;
                        w_disp_tx_en <= 1;
                        state <= S_SUM_CHECK;
                    end
                end

                // 3. 循环检查: 还有没有下一个规格?
                S_SUM_CHECK: begin
                    // 这里 o_lut_idx_req 既是计数器也是输出
                    if (o_lut_idx_req < i_system_types_count) begin
                        // 还有数据，FSM 会根据 o_lut_idx_req 更新 w_disp_m/n/cnt
                        // 我们需要等一拍让数据稳定吗？通常不用，如果是组合逻辑
                        state <= S_SUM_M; 
                    end else begin
                        state <= S_DONE; // 遍历完了
                    end
                end

                // 4. 发送序列: M * N * Cnt + Space
                S_SUM_M: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_disp_m[7:0] + ASC_0; 
                        w_disp_tx_en <= 1;
                        state <= S_SUM_STAR1;
                    end
                end
                S_SUM_STAR1: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_STAR; 
                        w_disp_tx_en <= 1;
                        state <= S_SUM_N;
                    end
                end
                S_SUM_N: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_disp_n[7:0] + ASC_0; 
                        w_disp_tx_en <= 1;
                        state <= S_SUM_STAR2;
                    end
                end
                S_SUM_STAR2: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_STAR; 
                        w_disp_tx_en <= 1;
                        state <= S_SUM_CNT;
                    end
                end
                S_SUM_CNT: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= {6'b0, w_disp_total_cnt} + ASC_0; 
                        w_disp_tx_en <= 1;
                        state <= S_SUM_SP2;
                    end
                end
                S_SUM_SP2: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= ASC_SPACE; 
                        w_disp_tx_en <= 1;
                        // 准备查下一个
                        o_lut_idx_req <= o_lut_idx_req + 1; 
                        state <= S_SUM_CHECK;
                    end
                end

                // ============================================================
                // 列表模式 / 单矩阵模式逻辑 
                // ============================================================
                S_LIST_SHOW_ID: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= (mat_idx + 1) + ASC_0; 
                        w_disp_tx_en <= 1;
                        state <= S_LIST_ID_LF;
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
                            state <= S_LIST_REQ;
                        end
                    end
                end

                S_LIST_REQ: begin
                    // 地址计算：Base + (idx * m * n) + (row * n) + col
                    w_disp_req_addr <= w_disp_base_addr + 
                                       (mat_idx * w_disp_m * w_disp_n) + 
                                       (row_cnt * w_disp_n) + 
                                       col_cnt;
                    state <= S_LIST_WAIT;
                end

                S_LIST_WAIT: begin
                    state <= S_LIST_SEND;
                end

                S_LIST_SEND: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= w_storage_rdata[7:0] + ASC_0;
                        w_disp_tx_en <= 1;
                        // 写入缓存 (Mode 0 也会顺便更新缓存的第0个位置，通常无害)
                        mat_cache[(mat_idx * 25) + (row_cnt * w_disp_n) + col_cnt] <= w_storage_rdata;
                        state <= S_LIST_SEP;
                        tx_step <= 0;
                    end
                end

                S_LIST_SEP: begin
                    if (w_tx_ready) begin
                        if (col_cnt == w_disp_n - 1) begin
                            // 行末换行
                            if (tx_step == 0) begin
                                w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1;
                            end else begin
                                w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1;
                                col_cnt <= 0;
                                if (row_cnt == w_disp_m - 1) begin
                                    // 矩阵结束
                                    mat_idx <= mat_idx + 1;
                                    // 检查是否还有下一个 (对于 Mode 0，total_cnt 应为 1，这里直接不成立跳转 DONE)
                                    if (mat_idx + 1 < w_disp_total_cnt) begin
                                        state <= S_LIST_SHOW_ID; 
                                    end else begin
                                        state <= S_DONE; 
                                    end
                                end else begin
                                    row_cnt <= row_cnt + 1;
                                    state <= S_LIST_REQ; 
                                end
                            end
                        end else begin
                            // 行中空格
                            w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1;
                            col_cnt <= col_cnt + 1;
                            state <= S_LIST_REQ; 
                        end
                    end
                end

                // ============================================================
                // 缓存回显模式 (逻辑类似 List，但读的是 mat_cache)
                // ============================================================
                S_CACHE_FETCH: begin
                    // 1. 从缓存读数据 (组合逻辑读取，无需等待)
                    // 地址 = (mat_idx * 25) + (row_cnt * n) + col_cnt
                    // 注意：这里使用 r_cached_n
                    cache_rdata <= mat_cache[(mat_idx * 25) + (row_cnt * r_cached_n) + col_cnt];
                    state <= S_CACHE_SEND;
                end

                S_CACHE_SEND: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= cache_rdata[7:0] + ASC_0; // 转 ASCII
                        w_disp_tx_en <= 1;
                        state <= S_CACHE_SEP;
                        tx_step <= 0;
                    end
                end

                S_CACHE_SEP: begin
                    if (w_tx_ready) begin
                        if (col_cnt == r_cached_n - 1) begin
                            // 行末换行
                            if (tx_step == 0) begin
                                w_disp_tx_data <= ASC_CR; w_disp_tx_en <= 1; tx_step <= 1;
                            end else begin
                                w_disp_tx_data <= ASC_LF; w_disp_tx_en <= 1;
                                col_cnt <= 0;
                                // 检查是否发完
                                if (row_cnt == r_cached_m - 1) begin
                                    state <= S_DONE; // 单个矩阵发完即结束
                                end else begin
                                    row_cnt <= row_cnt + 1;
                                    state <= S_CACHE_FETCH;
                                end
                            end
                        end else begin
                            // 行中空格
                            w_disp_tx_data <= ASC_SPACE; w_disp_tx_en <= 1;
                            col_cnt <= col_cnt + 1;
                            state <= S_CACHE_FETCH;
                        end
                    end
                end

                S_DONE: begin
                    w_disp_done <= 1;
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule