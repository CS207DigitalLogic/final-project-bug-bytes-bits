module Input_Subsystem (
    input clk, rst_n, uart_rx, w_en_input,
    // FSM 交互接口
    input [7:0] w_base_addr,      // FSM 分配的基地址
    input w_addr_ready,           // FSM 通知：地址分配好了
    input w_is_gen_mode,          // 1=生成模式, 0=输入模式

    // 任务模式控制
    // 0 = 完整存储模式 (Storage Mode)
    // 1 = 仅读取维度 (Read Dim Only)
    // 2 = 仅读取ID (Read ID Only)
    input [1:0] w_task_mode, 

    output reg w_input_we,
    output wire [7:0] w_real_addr, // 最终物理地址
    output reg [31:0] w_input_data,
    output reg w_rx_done,         // 任务完成信号
    output reg w_error_flag,      // 错误标志
    
    // 握手接口
    output wire [31:0] w_dim_m, 
    output wire [31:0] w_dim_n,
    output reg w_dims_valid,      // 请求分配地址 / 维度读取完成
    
    // ID 读取接口
    output reg [31:0] w_input_id_val,
    output reg w_id_valid         // ID 读取完成标志
);

    // 参数定义 
    parameter ASC_0     = 48;
    parameter ASC_SPACE = 32;
    parameter ASC_CR    = 13; // \r
    parameter ASC_LF    = 10; // \n

    // 状态机状态定义
    localparam S_RX_M       = 0; // 接收 m (或 ID)
    localparam S_RX_N       = 1; // 接收 n
    localparam S_RX_COUNT   = 2; // 接收生成数量 (仅生成模式)
    localparam S_WAIT_ADDR  = 3; // 等待 FSM 分配地址
    localparam S_WRITE_HEAD = 4; // 写入头信息 (m, n)
    localparam S_PRE_CLEAR  = 5; // 预清零 (输入模式刷0)
    localparam S_USER_INPUT = 6; // 用户输入数据 (覆盖0)
    localparam S_GEN_FILL   = 7; // 自动填充随机数 (生成模式)
    localparam S_DONE       = 8; // 结束

    // --- 内部寄存器 ---
    reg [31:0] current_value;
    reg [31:0] reg_m, reg_n, expected_count;
    reg [7:0]  w_input_addr; // 相对地址计数器
    
    // 生成模式专用
    reg [31:0] gen_total_mats; // 总共要生成几个 (1或2)
    reg [31:0] gen_curr_cnt;   // 当前生成到第几个
    reg [31:0] lfsr_reg;       // 伪随机数种子

    // 状态机寄存器
    reg [3:0] state;
    reg [1:0] header_cnt;      // 头信息写入计数

    // 连线与实例化
    wire [7:0] rx_data;
    wire rx_pulse;
    
    assign w_real_addr = w_input_addr + w_base_addr; // 物理地址 = 相对 + 基址
    assign w_dim_m = reg_m;
    assign w_dim_n = reg_n;

    // 简单的伪随机数生成 (取低4位模10)
    wire [31:0] random_val = lfsr_reg[3:0] % 10; 
    always @(posedge clk) begin
        if (!rst_n) lfsr_reg <= 32'hACE1;
        else lfsr_reg <= {lfsr_reg[30:0], lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1]};
    end

    // UART 驱动实例化
    uart_rx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_done(rx_pulse)
    );

    // 主逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_value <= 0;
            w_input_addr <= 0; w_input_we <= 0; w_input_data <= 0;
            w_error_flag <= 0; w_rx_done <= 0; w_dims_valid <= 0;
            
            // [新增] 复位新接口
            w_input_id_val <= 0; w_id_valid <= 0;

            state <= S_RX_M;
            header_cnt <= 0;
            reg_m <= 0; reg_n <= 0; expected_count <= 25;
            gen_total_mats <= 0; gen_curr_cnt <= 0;
        end
        else if (w_en_input) begin
            w_error_flag <= 0; // 默认拉低 (脉冲)
            w_input_we <= 0;
            w_dims_valid <= 0; // 请求信号脉冲复位
            w_id_valid <= 0;   // ID有效信号脉冲复位

            case (state)
                // 1. 接收行数 m (或者 ID)
                S_RX_M: if (rx_pulse) begin
                    if (rx_data >= ASC_0 && rx_data <= ASC_0+9) 
                        current_value <= current_value * 10 + (rx_data - ASC_0);
                    else if (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF) begin
                        //  分支: 仅读取 ID 模式 (Mode 2)
                        if (w_task_mode == 2) begin
                            w_input_id_val <= current_value; // 输出 ID
                            w_id_valid <= 1;                 // 握手信号
                            current_value <= 0;
                            state <= S_DONE;                 // 任务直接结束
                        end
                        // 原始分支: 读取 M
                        else if (current_value >= 1 && current_value <= 5) begin
                            reg_m <= current_value;
                            current_value <= 0;
                            state <= S_RX_N;
                        end else w_error_flag <= 1; // 维度非法
                    end else w_error_flag <= 1;
                end

                // 2. 接收列数 n
                S_RX_N: if (rx_pulse) begin
                    if (rx_data >= ASC_0 && rx_data <= ASC_0+9) 
                        current_value <= current_value * 10 + (rx_data - ASC_0);
                    else if (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF) begin
                        if (current_value >= 1 && current_value <= 5) begin
                            reg_n <= current_value;
                            expected_count <= reg_m * current_value; // 计算总元素数
                            current_value <= 0;
                            
                            // 分支: 仅读取维度模式 (Mode 1)
                            if (w_task_mode == 1) begin
                                w_dims_valid <= 1; // 借用此信号表示“维度读取完毕”
                                state <= S_DONE;   // 任务直接结束，不申请地址
                            end
                            // 原始分支: 存储/生成模式 (Mode 0)
                            else begin
                                // [分流] 生成模式去读数量，输入模式直接去要地址
                                if (w_is_gen_mode) state <= S_RX_COUNT;
                                else begin 
                                    gen_total_mats <= 1; // 输入模式默认只存1个
                                    gen_curr_cnt <= 0;
                                    state <= S_WAIT_ADDR; 
                                end
                            end
                        end else w_error_flag <= 1;
                    end else w_error_flag <= 1;
                end

                // 3. 接收生成数量 (仅生成模式)
                S_RX_COUNT: if (rx_pulse) begin
                    if (rx_data >= ASC_0 && rx_data <= ASC_0+9) 
                        current_value <= current_value * 10 + (rx_data - ASC_0);
                    else if (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF) begin
                        if (current_value >= 1 && current_value <= 2) begin
                            gen_total_mats <= current_value;
                            gen_curr_cnt <= 0;
                            current_value <= 0;
                            state <= S_WAIT_ADDR; // 齐活了，去要地址
                        end else w_error_flag <= 1;
                    end else w_error_flag <= 1;
                end

                // 4. 向 FSM 申请基地址
                S_WAIT_ADDR: begin
                    w_dims_valid <= 1; // 拉高请求信号
                    if (w_addr_ready) begin
                        state <= S_WRITE_HEAD; // 拿到地址，去写头信息
                        header_cnt <= 0;
                    end
                end

                // 5. 写入头信息 (m, n)
                S_WRITE_HEAD: begin
                    w_input_we <= 1;
                    if (header_cnt == 0) begin
                        w_input_addr <= 0; // 相对地址0
                        w_input_data <= reg_m;
                        header_cnt <= 1;
                    end 
                    else if (header_cnt == 1) begin
                        w_input_addr <= 1; // 相对地址1
                        w_input_data <= reg_n;
                        
                        // [分流] 决定下一步去哪
                        w_input_addr <= 2; // 准备操作数据区
                        if (w_is_gen_mode) state <= S_GEN_FILL;
                        else state <= S_PRE_CLEAR;
                    end
                end

                // 6. 输入模式分支: 预清零 (Pre-Clear)
                S_PRE_CLEAR: begin
                    // 刷0
                    w_input_we <= 1;
                    w_input_data <= 0;
                    if ((w_input_addr - 2) < expected_count - 1) begin
                        w_input_addr <= w_input_addr + 1;
                    end else begin
                        w_input_we <= 0;
                        w_input_addr <= 2; // 指针回退，等待用户输入覆盖
                        state <= S_USER_INPUT;
                    end
                end

                // 7. 输入模式分支: 用户输入 (覆盖0)
                S_USER_INPUT: if (rx_pulse) begin
                    if (rx_data >= ASC_0 && rx_data <= ASC_0+9) 
                        current_value <= current_value * 10 + (rx_data - ASC_0);
                    else if (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF) begin
                        if (current_value > 9) w_error_flag <= 1;
                        else if ((w_input_addr - 2) < expected_count) begin
                            w_input_data <= current_value;
                            w_input_we <= 1;
                            w_input_addr <= w_input_addr + 1;
                        end
                        current_value <= 0;
                    end
                    else w_error_flag <= 1;
                end

                // 8. 生成模式分支: 自动填充随机数
                S_GEN_FILL: begin
                    w_input_we <= 1;
                    w_input_data <= random_val; // 填入随机数
                    
                    if ((w_input_addr - 2) < expected_count - 1) begin
                        w_input_addr <= w_input_addr + 1;
                    end else begin
                        // 当前矩阵填完了
                        w_input_we <= 0;
                        gen_curr_cnt <= gen_curr_cnt + 1;
                        
                        // 检查是否需要生成第二个矩阵
                        if (gen_curr_cnt + 1 < gen_total_mats) begin
                            // 需要第二个，回到等待状态，再次请求 FSM 给新地址
                            state <= S_WAIT_ADDR; 
                        end else begin
                            // 全部完成
                            w_rx_done <= 1;
                            state <= S_DONE;
                        end
                    end
                end
                
                // 9. 结束状态
                S_DONE: begin
                    w_rx_done <= 1; // 保持完成信号
                end

            endcase
        end
        else begin // 非使能状态复位
            state <= S_RX_M;
            w_input_addr <= 0; 
            current_value <= 0;
            w_error_flag <= 0;
            w_input_we <= 0;
            w_rx_done <= 0;
        end
    end

endmodule