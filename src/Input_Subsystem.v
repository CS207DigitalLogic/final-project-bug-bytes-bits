`timescale 1ns / 1ps

module Input_Subsystem (
    input wire clk, 
    input wire rst_n, 
    input wire uart_rx, 
    input wire w_en_input, //FSM控制使能
    input wire [8:0] w_base_addr, //FSM给出的基地址     
    input wire w_addr_ready,  // FSM握手信号       
    input wire w_is_gen_mode, // 是否为生成模式        
    input wire [1:0] w_task_mode, // task_mode为0：输入/生成模式 1：读维度模式（计算过程用） 2：读编号模式（计算过程用）

    output reg w_input_we, 
    output wire [8:0] w_real_addr, 
    output reg [31:0] w_input_data, 
    output reg w_rx_done, //输入完全结束    
    output reg w_error_flag, // 1=输入有误(开启外部倒计时)，0=正常
    
    output wire [31:0] w_dim_m, //给FSM的第一个维度
    output wire [31:0] w_dim_n, //给FSM的第二个维度
    output reg w_dims_valid, //给FSM的信号，拉高后请求地址
    output reg [31:0] w_input_id_val, 
    output reg w_id_valid         
);
    localparam ASC_0     = 8'd48;
    localparam ASC_SPACE = 8'd32;
    localparam ASC_CR    = 8'd13;
    localparam ASC_LF    = 8'd10;

    localparam S_RX_M       = 0;
    localparam S_RX_N       = 1; 
    localparam S_RX_COUNT   = 2;
    localparam S_WAIT_ADDR  = 3; 
    localparam S_PRE_CLEAR  = 4; 
    localparam S_USER_INPUT = 5; 
    localparam S_GEN_FILL   = 6;
    localparam S_GEN_WAIT   = 8;
    localparam S_DONE       = 7; 

    localparam S_ERROR_FLUSH = 9;

    localparam TIMEOUT_MAX = 32'd30_000_000; //最大超时限制，如果在这个实现内未收到rx_pulse则自动跳到done（当输入补全补零的配合）


    reg [3:0] state, next_state;//状态寄存器
    reg [31:0] current_value; //寄存当前从串口读取的值是多少
    reg [31:0] reg_m, reg_n, expected_count;
    reg [8:0]  w_input_addr; //逻辑地址
    
    reg [31:0] gen_total_mats;
    reg [31:0] gen_curr_cnt;
    reg [31:0] lfsr_reg; //移位寄存器
    wire [31:0] random_val;

    reg [31:0] timeout_cnt; //检测超时寄存器

    wire [7:0] rx_data;
    wire rx_pulse;
    wire is_digit; //是数字
    wire is_delimiter; //是分隔符
    assign is_digit = (rx_data >= ASC_0 && rx_data <= ASC_0+9);
    assign is_delimiter = (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF); //空格|回车|换行
    assign w_real_addr = w_input_addr + w_base_addr; //真实地址异步分配
    assign w_dim_m = reg_m;
    assign w_dim_n = reg_n;
    
    assign random_val = lfsr_reg[31:0] % 10;

    always @(posedge clk) begin  //伪随机数生成，用于矩阵的随机数生成
        if (!rst_n) lfsr_reg <= 32'hACE1;
        else lfsr_reg <= {lfsr_reg[30:0], lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1]};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 0;
        end else begin
            if (state == S_USER_INPUT) begin
                if (rx_pulse) begin
                    // 如果检测到有数据输入（无论是数字还是分隔符），重置计时
                    timeout_cnt <= 0;
                end else if (timeout_cnt < TIMEOUT_MAX) begin
                    // 没有数据时，持续计时
                    timeout_cnt <= timeout_cnt + 1;
                end
            end 
            else begin
                // 其他状态下清零计数器
                timeout_cnt <= 0;
            end
        end
    end

    uart_rx #(
        .CLK_FREQ(25_000_000),//分频后需要除以四
        .BAUD_RATE(115200)
    ) u_uart_rx (
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
            S_RX_M: begin //读取第一个维度
                if (rx_pulse && is_delimiter) begin//这些都提前预测输入值是否正确，从而确定状态跳转逻辑
                    if (w_error_flag) next_state = S_ERROR_FLUSH; //如果报错了就忽略之后的输入
                    else if (current_value >= 1 && current_value <= 5) next_state = S_RX_N; //输入值合法，则跳到读取第二个维度
                    else begin
                        // 如果是回车结束的，直接重置等待下一次输入
                        if (rx_data == ASC_CR || rx_data == ASC_LF) next_state = S_RX_M;
                        // 如果是空格结束的（后面还有数据），进入 Flush 状态吞掉剩余输入
                        else next_state = S_ERROR_FLUSH;
                    end
                end
            end

            S_RX_N: begin //读取第二个维度
                if (rx_pulse && is_delimiter) begin
                    if (w_error_flag) next_state = S_ERROR_FLUSH;
                    else if (current_value >= 1 && current_value <= 5) begin
                        if (w_is_gen_mode) next_state = S_RX_COUNT; //状态合法并且是生成模式，则跳到读count（要生成几个矩阵）
                        else next_state = S_WAIT_ADDR; //状态合法并且是输入模式， 则跳到等FSM分配地址
                    end
                    else begin
                        //N 输入不合法
                        if (rx_data == ASC_CR || rx_data == ASC_LF) next_state = S_RX_M;
                        else next_state = S_ERROR_FLUSH;
                    end
                end
            end

            S_RX_COUNT: begin
                if (rx_pulse && is_delimiter) begin

                    if (current_value >= 1 && current_value <= 2) next_state = S_WAIT_ADDR; //只允许生成1个或者2个矩阵，成功就等待FSM分配地址
                    else begin
                        if (rx_data == ASC_CR || rx_data == ASC_LF) next_state = S_RX_M;
                        else next_state = S_ERROR_FLUSH;
                    end
                end
            end

            S_WAIT_ADDR: begin
                if (w_addr_ready) begin //接收到FSM的握手信号就跳转到下一个状态
                    if (w_is_gen_mode) next_state = S_GEN_FILL;
                    else next_state = S_PRE_CLEAR;
                end
            end

            S_PRE_CLEAR: begin //预清零模式，保证输入不齐能自动补0
                if (w_input_addr >= expected_count-1) next_state = S_USER_INPUT;
            end

            S_USER_INPUT: begin
                if (rx_pulse && is_delimiter) begin
                    // 提前判断，输入完最后一个数立刻结束，无需多按一次
                    //加入这个是因为防止最后一个数是错的，但是直接跳到done了，或者把最后一个块移到前面也行
                    if (w_input_addr >= expected_count - 1 && !w_error_flag) next_state = S_DONE; //expected_count 是m*n，也就是需要读取多少次，当读取完成跳到done
                    else if (rx_data == ASC_CR || rx_data == ASC_LF) begin
                        if (!w_error_flag) next_state = S_DONE; 
                        // 如果有错，就忽略回车，或者只用来清除错误标志，强制用户继续输入
                    end
                    else begin
                        if (w_error_flag) next_state = S_ERROR_FLUSH;
                    end
                end                    
                else if (timeout_cnt >= TIMEOUT_MAX) begin //输入不全补零或报错
                    if (w_error_flag) next_state = S_RX_M;
                    next_state = S_DONE;
                end
            end

            S_GEN_FILL: begin
                if (w_input_addr >= expected_count-1) begin //关于这里为什么要-1：w_input_addr从0开始
                    if (gen_curr_cnt + 1 < gen_total_mats) next_state = S_WAIT_ADDR;
                    else next_state = S_GEN_WAIT;
                end
            end

            S_ERROR_FLUSH: begin
                if (rx_pulse && (rx_data == ASC_CR || rx_data == ASC_LF)) begin
                    next_state = S_RX_M;
                end
                else if (timeout_cnt >= TIMEOUT_MAX) begin//timeout之后才会跳到S_RX_M（目前第一个块不会被触发，不知道是检测不到串口的换行还是什么原因）
                    next_state = S_RX_M; 
                end
            end

            S_GEN_WAIT: next_state = S_DONE;
            S_DONE: next_state = S_DONE;
            default: next_state = S_RX_M;
        endcase
    end

    // =========================================================================
    // Stage 3: 数据输出
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_value <= 0;
            w_input_addr <= 0; w_input_we <= 0; w_input_data <= 0;
            w_error_flag <= 0; w_rx_done <= 0; w_dims_valid <= 0;
            w_input_id_val <= 0; w_id_valid <= 0;
            reg_m <= 0; reg_n <= 0; expected_count <= 25;
            gen_total_mats <= 0; gen_curr_cnt <= 0;
        end
        else if (w_en_input) begin
            w_input_we <= 0;
            w_dims_valid <= 0;     
            w_id_valid <= 0;
            w_rx_done <= 0;

            if (w_input_we) w_input_addr <= w_input_addr + 1;//全局的地址更新逻辑，如果写使能信号被拉高就增加地址

            case (state)
                S_RX_M: begin
                    if (rx_pulse) begin
                        if (is_digit) begin
                            if (!w_error_flag) begin
                                    current_value <= current_value * 10 + (rx_data - ASC_0); //如果是数字就让它先存着，等遇到空格再统一判断
                                end
                        end
                        else if (is_delimiter) begin
                            if (w_task_mode == 2) begin  //读矩阵编号模式(id)
                                w_input_id_val <= current_value;
                                w_id_valid <= 1;
                            end else begin
                                if (current_value < 1 || current_value > 5) w_error_flag <= 1;
                                else begin
                                    reg_m <= current_value;
                                    w_error_flag <= 0;
                                end
                            end
                            current_value <= 0;
                        end
                        else begin 
                            w_error_flag <= 1;
                            current_value <= 0;
                        end
                    end
                end

                S_RX_N: begin
                    if (rx_pulse) begin
                        if (is_digit) begin 
                            w_error_flag <= 0;
                            current_value <= current_value * 10 + (rx_data - ASC_0);
                        end
                        else if (is_delimiter) begin
                            if (current_value < 1 || current_value > 5) begin
                                w_error_flag <= 1; 
                                current_value <= 0;
                            end else begin
                                reg_n <= current_value;
                                expected_count <= reg_m * current_value; //期望读入的数据规模为m*n
                                if (w_task_mode == 1) w_dims_valid <= 1; //读矩阵维度模式
                                else begin
                                    gen_total_mats <= 1;
                                    gen_curr_cnt <= 0;
                                end
                                w_error_flag <= 0;
                                current_value <= 0;
                            end
                        end
                        else begin
                            w_error_flag <= 1;
                            current_value <= 0;
                        end
                    end
                end

                S_RX_COUNT: begin//这是生成模式的读取生成数量模式
                    if (rx_pulse) begin
                        if (is_digit) begin
                            w_error_flag <= 0;
                            current_value <= current_value * 10 + (rx_data - ASC_0);
                        end
                        else if (is_delimiter) begin
                            if (current_value < 1 || current_value > 2) begin//只能为1或者2
                                w_error_flag <= 1;
                                current_value <= 0;
                            end else begin
                                gen_total_mats <= current_value; //赋值
                                gen_curr_cnt <= 0;
                                w_error_flag <= 0;
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
                    if (w_addr_ready) begin //地址好了就拉低w_dims_valid信号，但是这块在维度错误的时候接不到FSM的握手
                        w_dims_valid <= 0;
                        w_input_addr <= 0; 
                    end else begin
                        w_dims_valid <= 1;//信号默认保持
                    end
                end

                S_PRE_CLEAR: begin 
                    if (w_input_addr < expected_count-1) begin
                        w_input_we <= 1;
                        w_input_data <= 0; //把0都送给MUX清零即将填入的地址
                    end else begin
                        w_input_addr <= 0;
                    end
                end

                S_USER_INPUT: begin
                    if (rx_pulse) begin
                        if (is_digit) begin
                            w_error_flag <= 0;
                            if (current_value * 10 + (rx_data - ASC_0) > 9) begin
                                w_error_flag <= 1;
                                current_value <= 0;
                            end else begin
                                current_value <= current_value * 10 + (rx_data - ASC_0);
                            end
                        end
                        else if (is_delimiter) begin
                            if (w_error_flag) begin
                                w_error_flag <= 1;
                            end
                            else if (current_value > 9) begin
                                w_error_flag <= 1;
                                current_value <= 0;
                            end
                            else if (w_input_addr < expected_count) begin
                                w_input_we <= 1;
                                w_input_data <= current_value;
                                w_error_flag <= 0; 
                                current_value <= 0;
                            end
                        end
                        else begin 
                            w_error_flag <= 1;
                            current_value <= 0;
                        end
                    end
                end

                S_GEN_FILL: begin
                    if (w_input_addr < expected_count-1) begin
                        w_input_we <= 1;
                        w_input_data <= random_val;
                    end else begin
                        gen_curr_cnt <= gen_curr_cnt + 1;
                    end
                end

                S_ERROR_FLUSH: begin
                    if (timeout_cnt >= TIMEOUT_MAX || (rx_pulse && (rx_data == ASC_CR || rx_data == ASC_LF))) //timeout之后并且错误，跳回重新输入状态，同时清除错误
                        w_error_flag <= 0;
                    else 
                        w_error_flag <= 1; 
                    current_value <= 0;
                end

                S_GEN_WAIT: w_input_we <= 0;
                S_DONE: w_rx_done <= 1;
            endcase
        end
        else begin 
            w_rx_done <= 0;
            current_value <= 0;
            w_input_addr <= 0;
            w_error_flag <= 0; 
            w_dims_valid <= 0; //这玩意必须复位，要不然FSM会状态死循环
            w_id_valid <= 0; //这个同理
        end
    end

endmodule