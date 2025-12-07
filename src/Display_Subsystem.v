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
        .CLK_FREQ(100_000_000), // 请根据你的时钟频率修改
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
                    
                    if (w_disp_mode == 1) begin // 列表模式 (存缓存)
                        state <= S_LIST_SHOW_ID;
                        // 锁存维度，供缓存模式使用
                        r_cached_m <= w_disp_m;
                        r_cached_n <= w_disp_n;
                    end
                    else if (w_disp_mode == 3) begin // 缓存回显模式
                        state <= S_CACHE_FETCH;
                        // 校验一下 ID 是否合法，防止越界 (默认 ID 1)
                        if (w_disp_selected_id == 2) mat_idx <= 1; // ID 2 对应 index 1
                        else mat_idx <= 0;                         // ID 1 对应 index 0
                    end
                    else state <= S_DONE; 
                end

                // ----------------------------------------------------
                // 1. 显示编号 (如 "1" + \r\n)
                // ----------------------------------------------------
                S_LIST_SHOW_ID: begin
                    if (w_tx_ready) begin
                        w_disp_tx_data <= (mat_idx + 1) + ASC_0; // 0->'1', 1->'2'
                        w_disp_tx_en <= 1;
                        state <= S_LIST_ID_LF;
                        tx_step <= 0;
                    end
                end

                S_LIST_ID_LF: begin
                    if (w_tx_ready) begin
                        if (tx_step == 0) begin
                            w_disp_tx_data <= ASC_CR; // \r
                            w_disp_tx_en <= 1;
                            tx_step <= 1;
                        end else begin
                            w_disp_tx_data <= ASC_LF; // \n
                            w_disp_tx_en <= 1;
                            
                            // 准备开始打印矩阵内容
                            row_cnt <= 0;
                            col_cnt <= 0;
                            state <= S_LIST_REQ;
                        end
                    end
                end

                // ----------------------------------------------------
                // 2. 读取并显示矩阵内容 (m*n)
                // ----------------------------------------------------
                S_LIST_REQ: begin
                    // 计算物理地址: Base + (矩阵偏移) + (行偏移) + 列偏移
                    // 矩阵偏移 = mat_idx * (m * n)
                    w_disp_req_addr <= w_disp_base_addr + 
                                       (mat_idx * w_disp_m * w_disp_n) + 
                                       (row_cnt * w_disp_n) + 
                                       col_cnt;
                    
                    state <= S_LIST_WAIT;
                end

                S_LIST_WAIT: begin
                    // 等待 RAM 数据读出
                    state <= S_LIST_SEND;
                end

                S_LIST_SEND: begin
                    if (w_tx_ready) begin
                        // 将读到的二进制数转 ASCII 发送
                        w_disp_tx_data <= w_storage_rdata[7:0] + ASC_0;
                        w_disp_tx_en <= 1;
                        //写入缓存
                        mat_cache[(mat_idx * 25) + (row_cnt * w_disp_n) + col_cnt] <= w_storage_rdata;
                        state <= S_LIST_SEP;
                        tx_step <= 0;
                    end
                end

                S_LIST_SEP: begin
                    if (w_tx_ready) begin
                        // 判断是行末还是中间
                        if (col_cnt == w_disp_n - 1) begin
                            // 行末：发送 \r\n
                            if (tx_step == 0) begin
                                w_disp_tx_data <= ASC_CR;
                                w_disp_tx_en <= 1;
                                tx_step <= 1;
                            end else begin
                                w_disp_tx_data <= ASC_LF;
                                w_disp_tx_en <= 1;
                                // 换行处理
                                col_cnt <= 0;
                                
                                // 检查矩阵是否结束
                                if (row_cnt == w_disp_m - 1) begin
                                    // 当前矩阵打印完毕
                                    mat_idx <= mat_idx + 1;
                                    // 检查是否有下一个矩阵
                                    if (mat_idx + 1 < w_disp_total_cnt) begin
                                        state <= S_LIST_SHOW_ID; // 循环，显示下一个ID
                                    end else begin
                                        state <= S_DONE; // 全部结束
                                    end
                                end else begin
                                    row_cnt <= row_cnt + 1;
                                    state <= S_LIST_REQ; // 继续打印下一行
                                end
                            end
                        end 
                        else begin
                            // 行中：发送空格
                            w_disp_tx_data <= ASC_SPACE;
                            w_disp_tx_en <= 1;
                            col_cnt <= col_cnt + 1;
                            state <= S_LIST_REQ; // 继续打印下一个数
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