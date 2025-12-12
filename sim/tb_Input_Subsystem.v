`timescale 1ns / 1ps

module tb_Input_Subsystem;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    reg clk;
    reg rst_n;
    reg uart_rx_line; // 模拟串口线
    reg w_en_input;
    
    // FSM 模拟信号
    reg [7:0] w_base_addr;
    reg w_addr_ready;
    reg w_is_gen_mode;
    reg [1:0] w_task_mode;

    // 观察输出
    wire w_input_we;
    wire [7:0] w_real_addr;
    wire [31:0] w_input_data;
    wire w_rx_done;
    wire w_error_flag;
    wire [31:0] w_dim_m, w_dim_n;
    wire w_dims_valid;
    wire [31:0] w_input_id_val;
    wire w_id_valid;

    // =========================================================
    // 2. 参数设置 (必须与源码一致)
    // =========================================================
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD_RATE = 115200;
    // 计算一位需多少纳秒: 10^9 / 115200 ≈ 8680.55 ns
    parameter BIT_PERIOD = 8680; 
    parameter CLK_PERIOD = 10;   // 100MHz = 10ns

    // =========================================================
    // 3. 模块例化 (DUT: Device Under Test)
    // =========================================================
    Input_Subsystem dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        
        // FSM 接口
        .w_base_addr(w_base_addr),
        .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode),
        .w_task_mode(w_task_mode),
        
        // 输出观测
        .w_input_we(w_input_we),
        .w_real_addr(w_real_addr),
        .w_input_data(w_input_data),
        .w_rx_done(w_rx_done),
        .w_error_flag(w_error_flag),
        .w_dim_m(w_dim_m),
        .w_dim_n(w_dim_n),
        .w_dims_valid(w_dims_valid),
        .w_input_id_val(w_input_id_val),
        .w_id_valid(w_id_valid)
    );

    // =========================================================
    // 4. 时钟生成
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // 5. UART 发送任务 (模拟电脑发数据)
    // =========================================================
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // 1. 起始位 (Start Bit = 0)
            uart_rx_line = 0;
            #(BIT_PERIOD);
            
            // 2. 数据位 (LSB First)
            for (i=0; i<8; i=i+1) begin
                uart_rx_line = data[i];
                #(BIT_PERIOD);
            end
            
            // 3. 停止位 (Stop Bit = 1)
            uart_rx_line = 1;
            #(BIT_PERIOD);
            
            // 字节间稍微停顿一下，模拟真实情况
            #(BIT_PERIOD * 2);
        end
    endtask

    // =========================================================
    // 6. 测试主流程
    // =========================================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        uart_rx_line = 1; // 串口空闲为高电平
        w_en_input = 0;
        w_base_addr = 0;
        w_addr_ready = 0;
        w_is_gen_mode = 0;
        w_task_mode = 0;

        // --- 复位释放 ---
        #100;
        rst_n = 1;
        #100;

        $display("=== Test Start: Input Subsystem ===");

        // --- 场景 1: 输入 2x3 矩阵 ---
        // 目标输入: "2 3 " (维度) -> 等待分配 -> "4 5 6 7 8 9 " (数据)
        
        // 1. 启动模块
        w_en_input = 1;
        w_task_mode = 0; // Mode 0: 完整存储
        
        // 2. 发送维度 "2"
        uart_send_byte("2"); 
        uart_send_byte(" "); // 分隔符
        
        // 3. 发送维度 "3"
        uart_send_byte("3");
        uart_send_byte(" "); // 分隔符触发 w_dims_valid
        
        // 4. 模拟 FSM 响应 (握手)
        // 此时 DUT 应该拉高 w_dims_valid
        wait(w_dims_valid == 1);
        $display("[Time %t] Dimensions Received: %d x %d", $time, w_dim_m, w_dim_n);
        
        // FSM 分配基地址 (假设分配到 100)
        #200; 
        w_base_addr = 8'd100;
        w_addr_ready = 1; // 告诉 Input 地址好了
        #20;
        w_addr_ready = 0; // 脉冲结束
        
        // 等待 Input 模块完成 Pre-Clear (预清零)
        // 预清零需要 6 个周期，我们多等一会儿
        #500; 
        
        $display("[Time %t] Start Sending Matrix Data...", $time);

        // 5. 发送矩阵数据: 4, 5, 6, 7, 8, 9
        // 注意：每个数字后面都要跟空格
        uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" ");
        uart_send_byte("7"); uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte(" ");
        uart_send_byte("9"); uart_send_byte(" "); // 最后一个发完，应该触发 rx_done

        // 6. 检查完成信号
        wait(w_rx_done == 1);
        $display("[Time %t] Matrix Input Complete! rx_done detected.", $time);
        
        // 7. 结束测试
        w_en_input = 0;
        #1000;
        $stop;
    end

    // 实时监控写入操作
    always @(posedge clk) begin
        if (w_input_we) begin
            $display("[Storage Write] Addr: %d, Data: %d", w_real_addr, w_input_data);
        end
    end

endmodule