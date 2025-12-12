`timescale 1ns / 1ps

module tb_Generation_Mode;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    reg clk;
    reg rst_n;
    reg uart_rx_line;
    reg w_en_input;
    
    // FSM 模拟信号
    reg [7:0] w_base_addr;
    reg w_addr_ready;
    reg w_is_gen_mode;     // 关键：置1表示生成模式
    reg [1:0] w_task_mode;

    // 观察输出
    wire w_input_we;
    wire [7:0] w_real_addr;
    wire [31:0] w_input_data;
    wire w_rx_done;
    wire w_error_flag;
    wire [31:0] w_dim_m, w_dim_n;
    wire w_dims_valid;

    // 参数设置
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 8680; // 10^9 / 115200
    parameter CLK_PERIOD = 10;

    // =========================================================
    // 2. 模块例化
    // =========================================================
    Input_Subsystem dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr), .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_input_we(w_input_we), .w_real_addr(w_real_addr), .w_input_data(w_input_data),
        .w_rx_done(w_rx_done), .w_error_flag(w_error_flag),
        .w_dim_m(w_dim_m), .w_dim_n(w_dim_n), .w_dims_valid(w_dims_valid)
    );

    // =========================================================
    // 3. 基础驱动
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx_line = 0; #(BIT_PERIOD); // Start
            for (i=0; i<8; i=i+1) begin
                uart_rx_line = data[i]; #(BIT_PERIOD);
            end
            uart_rx_line = 1; #(BIT_PERIOD); // Stop
            #(BIT_PERIOD * 2);
        end
    endtask

    // =========================================================
    // 4. 测试主流程
    // =========================================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        uart_rx_line = 1;
        w_en_input = 0;
        w_addr_ready = 0;
        w_base_addr = 0;
        
        // --- 关键设置：生成模式 ---
        w_is_gen_mode = 1; 
        w_task_mode = 0;

        // --- 复位释放 ---
        #100; rst_n = 1; #100;
        w_en_input = 1; // 启动模块

        $display("=== Test Start: Matrix Generation Mode ===");

        // 1. 发送维度 "2" "3"
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        
        $display("[Time %t] Dimensions sent. Waiting for Count input...", $time);

        // 2. 发送生成数量 "2" (生成2个矩阵)
        uart_send_byte("2"); uart_send_byte(" ");

        // 3. 第一轮握手 (Matrix A)
        wait(w_dims_valid == 1);
        $display("[Time %t] Request 1 received. Allocating Addr 100...", $time);
        
        #200;
        w_base_addr = 8'd100; // 分配地址 100
        w_addr_ready = 1;
        #20;
        w_addr_ready = 0;

        // 等待第一轮生成结束 (6个数据)
        // 我们可以检测 w_dims_valid 再次变高，或者直接延时
        // 因为生成速度很快(1个周期写1个)，这里延时稍微长一点确保覆盖
        #500;

        // 4. 第二轮握手 (Matrix B)
        // 模块应该会自动再次拉高 w_dims_valid 请求第二个矩阵的地址
        wait(w_dims_valid == 1);
        $display("[Time %t] Request 2 received. Allocating Addr 200...", $time);
        
        #200;
        w_base_addr = 8'd200; // 分配地址 200
        w_addr_ready = 1;
        #20;
        w_addr_ready = 0;

        // 5. 等待结束
        wait(w_rx_done == 1);
        $display("[Time %t] Generation Complete! rx_done detected.", $time);

        #1000;
        $stop;
    end

    // 实时监控写入
    always @(posedge clk) begin
        if (w_input_we) begin
            $display("[GEN WRITE] Time: %t, Addr: %d, Data: %d (Random)", $time, w_real_addr, w_input_data);
        end
    end

endmodule