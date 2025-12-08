module Input_Subsystem (
    input wire clk, 
    input wire rst_n, 
    input wire uart_rx, 
    input wire w_en_input,
    // FSM 交互接口
    input wire [7:0] w_base_addr,      
    input wire w_addr_ready,           
    input wire w_is_gen_mode,          

    // 任务模式控制
    input wire [1:0] w_task_mode, 

    output reg w_input_we,
    output wire [7:0] w_real_addr, 
    output reg [31:0] w_input_data,
    output reg w_rx_done,         
    output reg w_error_flag,      
    
    // 握手接口
    output wire [31:0] w_dim_m, 
    output wire [31:0] w_dim_n,
    output reg w_dims_valid,      
    
    // ID 读取接口
    output reg [31:0] w_input_id_val,
    output reg w_id_valid         
);

    // =========================================================================
    // 参数定义
    // =========================================================================
    localparam ASC_0     = 8'd48;
    localparam ASC_SPACE = 8'd32;
    localparam ASC_CR    = 8'd13;
    localparam ASC_LF    = 8'd10;

    // 状态定义
    localparam S_RX_M       = 0; 
    localparam S_RX_N       = 1; 
    localparam S_RX_COUNT   = 2; 
    localparam S_WAIT_ADDR  = 3; 
    localparam S_PRE_CLEAR  = 4; 
    localparam S_USER_INPUT = 5; 
    localparam S_GEN_FILL   = 6; 
    localparam S_DONE       = 7; 

    parameter TIMEOUT_VAL = 32'd50_000_000;

    // =========================================================================
    // 内部信号
    // =========================================================================
    reg [3:0] state, next_state; 

    reg [31:0] current_value;
    reg [31:0] reg_m, reg_n, expected_count;
    reg [7:0]  w_input_addr; 
    
    reg [31:0] gen_total_mats;
    reg [31:0] gen_curr_cnt;   
    reg [31:0] lfsr_reg;
    wire [31:0] random_val;

    reg [31:0] timeout_cnt;

    wire [7:0] rx_data;
    wire rx_pulse;

    wire is_digit;
    wire is_delimiter;
    
    assign is_digit = (rx_data >= ASC_0 && rx_data <= ASC_0+9);
    assign is_delimiter = (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF);
    
    assign w_real_addr = w_input_addr + w_base_addr;
    assign w_dim_m = reg_m;
    assign w_dim_n = reg_n;
    
    assign random_val = lfsr_reg[3:0] % 10;
    always @(posedge clk) begin
        if (!rst_n) lfsr_reg <= 32'hACE1;
        else lfsr_reg <= {lfsr_reg[30:0], lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1]};
    end

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

    // =========================================================================
    // Stage 1: 状态跳转
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_RX_M;
        else if (w_en_input) state <= next_state;
        else state <= S_RX_M;
    end

    // =========================================================================
    // Stage 2: 次态逻辑 
    // =========================================================================
    always @(*) begin
        next_state = state; 

        case (state)
            S_RX_M: begin
                if (rx_pulse) begin
                    if (is_delimiter) begin
                        if (w_task_mode == 2) next_state = S_DONE; 
                        // 如果数值非法，保持在 S_RX_M 
                        else if (current_value >= 1 && current_value <= 5) next_state = S_RX_N;
                    end
                    else if (!is_digit) begin
                        // 收到非法字符，保持在 S_RX_M 
                    end
                end
            end

            S_RX_N: begin
                if (rx_pulse) begin
                    if (is_delimiter) begin
                        if (current_value >= 1 && current_value <= 5) begin
                            if (w_task_mode == 1) next_state = S_DONE; 
                            else if (w_is_gen_mode) next_state = S_RX_COUNT;
                            else next_state = S_WAIT_ADDR;
                        end
                        else next_state = S_RX_M; // 维度N错误 -> 回到起点
                    end
                    else if (!is_digit) next_state = S_RX_M; // 非法字符 -> 回到起点
                end
            end

            S_RX_COUNT: begin
                if (rx_pulse) begin
                    if (is_delimiter) begin
                        if (current_value >= 1 && current_value <= 2) next_state = S_WAIT_ADDR;
                        else next_state = S_RX_M; // [修改] 数量错误 -> 回到起点
                    end
                    else if (!is_digit) next_state = S_RX_M; // [修改] 非法字符 -> 回到起点
                end
            end

            S_WAIT_ADDR: begin
                if (w_addr_ready) begin
                    if (w_is_gen_mode) next_state = S_GEN_FILL;
                    else next_state = S_PRE_CLEAR;
                end
            end

            S_PRE_CLEAR: begin
                if (w_input_addr >= expected_count) next_state = S_USER_INPUT; 
            end

            S_USER_INPUT: begin
                if (timeout_cnt >= TIMEOUT_VAL) 
                    next_state = S_DONE;
                else if (rx_pulse) begin
                    if (is_delimiter) begin
                        if (current_value > 9) next_state = S_RX_M; 
                        else if (w_input_addr + 1 >= expected_count) next_state = S_DONE;
                    end
                    else if (!is_digit) next_state = S_RX_M; 
                end
            end

            S_GEN_FILL: begin
                if (w_input_addr >= expected_count) begin
                    if (gen_curr_cnt + 1 < gen_total_mats) next_state = S_WAIT_ADDR;
                    else next_state = S_DONE;
                end
            end

            S_DONE: next_state = S_DONE;
            default: next_state = S_RX_M;
        endcase
    end

    // =========================================================================
    // Stage 3: 数据输出与寄存器更新
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_value <= 0;
            w_input_addr <= 0; w_input_we <= 0; w_input_data <= 0;
            w_error_flag <= 0; w_rx_done <= 0; w_dims_valid <= 0;
            w_input_id_val <= 0; w_id_valid <= 0;
            reg_m <= 0; reg_n <= 0; expected_count <= 25;
            gen_total_mats <= 0; gen_curr_cnt <= 0;
            timeout_cnt <= 0;
        end
        else if (w_en_input) begin
            w_input_we <= 0;       
            w_dims_valid <= 0;     
            w_id_valid <= 0;
            w_rx_done <= 0;

            if (state != S_USER_INPUT || rx_pulse) timeout_cnt <= 0;
            else if (state == S_USER_INPUT && timeout_cnt < TIMEOUT_VAL) timeout_cnt <= timeout_cnt + 1;

            case (state)
                S_RX_M: begin
                    if (rx_pulse) begin
                        if (is_digit) begin
                            w_error_flag <= 0; // 重试输入数字时灭灯
                            current_value <= current_value * 10 + (rx_data - ASC_0);
                        end
                        else if (is_delimiter) begin
                            if (w_task_mode == 2) begin 
                                w_input_id_val <= current_value;
                                w_id_valid <= 1;
                            end else begin
                                if (current_value < 1 || current_value > 5) begin
                                    w_error_flag <= 1; // 报错
                                    // Stage 2 会保持在 S_RX_M
                                end else begin
                                    reg_m <= current_value;
                                    w_error_flag <= 0; 
                                end
                            end
                            current_value <= 0; 
                        end
                        else begin 
                            w_error_flag <= 1; // 非法字符
                            current_value <= 0;
                        end
                    end
                end

                S_RX_N: begin
                    if (rx_pulse) begin
                        if (is_digit) current_value <= current_value * 10 + (rx_data - ASC_0);
                        else if (is_delimiter) begin
                            if (current_value < 1 || current_value > 5) begin
                                w_error_flag <= 1; // 报错，Stage 2 将跳回 S_RX_M
                                current_value <= 0;
                            end else begin
                                reg_n <= current_value;
                                expected_count <= reg_m * current_value;
                                if (w_task_mode == 1) w_dims_valid <= 1; 
                                else begin
                                    gen_total_mats <= 1; 
                                    gen_curr_cnt <= 0;
                                end
                                current_value <= 0;
                            end
                        end
                        else begin
                            w_error_flag <= 1; // 非法字符，Stage 2 将跳回 S_RX_M
                            current_value <= 0;
                        end
                    end
                end

                S_RX_COUNT: begin
                    if (rx_pulse) begin
                        if (is_digit) current_value <= current_value * 10 + (rx_data - ASC_0);
                        else if (is_delimiter) begin
                            if (current_value < 1 || current_value > 2) begin
                                w_error_flag <= 1; // 报错，跳回 S_RX_M
                                current_value <= 0;
                            end else begin
                                gen_total_mats <= current_value;
                                gen_curr_cnt <= 0;
                                current_value <= 0;
                            end
                        end
                        else begin
                            w_error_flag <= 1; 
                            current_value <= 0;
                        end
                    end
                end

                S_WAIT_ADDR: begin
                    w_dims_valid <= 1; 
                    if (w_addr_ready) w_input_addr <= 0; 
                end

                S_PRE_CLEAR: begin
                    if (w_input_addr < expected_count) begin
                        w_input_we <= 1;
                        w_input_data <= 0;
                        w_input_addr <= w_input_addr + 1;
                    end else begin
                        w_input_addr <= 0; 
                    end
                end

                S_USER_INPUT: begin
                    if (rx_pulse) begin
                        if (is_digit) begin
                            if (current_value * 10 + (rx_data - ASC_0) > 9) begin
                                w_error_flag <= 1; // 实时数值越界，跳回 S_RX_M
                                current_value <= 0;
                            end else begin
                                current_value <= current_value * 10 + (rx_data - ASC_0);
                            end
                        end
                        else if (is_delimiter) begin
                            if (current_value > 9) begin
                                w_error_flag <= 1; // 数值确认越界，跳回 S_RX_M
                                current_value <= 0;
                            end
                            else if (w_input_addr < expected_count) begin
                                w_input_data <= current_value;
                                w_input_we <= 1;
                                w_input_addr <= w_input_addr + 1;
                                current_value <= 0;
                            end
                        end
                        else begin 
                            w_error_flag <= 1; // 非法字符，跳回 S_RX_M
                            current_value <= 0;
                        end
                    end
                end

                S_GEN_FILL: begin
                    if (w_input_addr < expected_count) begin
                        w_input_we <= 1;
                        w_input_data <= random_val;
                        w_input_addr <= w_input_addr + 1;
                    end else begin
                        gen_curr_cnt <= gen_curr_cnt + 1;
                    end
                end

                S_DONE: begin
                    w_rx_done <= 1;
                end
            endcase
        end
        else begin 
            // Disable 时复位
            w_rx_done <= 0;
            current_value <= 0;
            w_input_addr <= 0;
            w_error_flag <= 0; 
        end
    end

endmodule