`timescale 1ns / 1ps

module tb_Display_Format_Test;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    reg clk;
    reg rst_n;
    
    // 物理接口
    reg uart_rx_line;       // 模拟电脑发给 FPGA (Input)
    wire uart_tx_line;      // 模拟 FPGA 发给电脑 (Display Output)
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // 内部连线
    wire w_en_input, w_en_display, w_start_calc;
    wire [1:0] w_task_mode;
    wire [1:0] w_disp_mode;
    wire w_rx_done, w_disp_done;
    
    // 存储相关
    wire w_input_we, w_storage_we;
    wire [7:0] w_input_addr, w_storage_addr, w_disp_req_addr;
    wire [31:0] w_input_data, w_storage_wdata, w_storage_rdata;

    // 参数
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 8680; 
    parameter CLK_PERIOD = 10;

    // =========================================================
    // 2. 模块集成 (System Integration)
    // =========================================================

    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .sw(sw), .btn(btn), .led(led),
        
        .w_en_input(w_en_input), .w_en_display(w_en_display),
        .w_task_mode(w_task_mode), 
        .w_disp_mode(w_disp_mode),
        
        // Input 交互
        .w_dims_valid(u_input.w_dims_valid), 
        .i_dim_m(u_input.w_dim_m), .i_dim_n(u_input.w_dim_n),
        .w_rx_done(u_input.w_rx_done), .w_error_flag(u_input.w_error_flag),
        .w_addr_ready(w_addr_ready), .w_base_addr_to_input(w_base_addr_to_input),
        
        // Display 交互
        .w_disp_done(u_disp.w_disp_done),
        .w_disp_base_addr(w_disp_base_addr), 
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_total_cnt(w_disp_total_cnt),
        
        // 其他置0
        .w_calc_done(0), .i_input_id_val(0), .w_id_valid(0)
    );
    
    // 补充 FSM 输出缺少的连线定义
    wire w_addr_ready;
    wire [7:0] w_base_addr_to_input;
    wire [7:0] w_disp_base_addr;
    wire [31:0] w_disp_m, w_disp_n;
    wire [1:0] w_disp_total_cnt;

    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr_to_input), .w_addr_ready(w_addr_ready),
        .w_task_mode(w_task_mode), .w_is_gen_mode(0),
        
        .w_input_we(w_input_we), .w_real_addr(w_input_addr), .w_input_data(w_input_data)
    );

    Display_Subsystem u_disp (
        .clk(clk), .rst_n(rst_n),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_storage_rdata(w_storage_rdata), .w_disp_req_addr(w_disp_req_addr),
        .uart_tx_pin(uart_tx_line) // 输出到 Testbench 观测
    );

    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(0),
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        .i_disp_addr(w_disp_req_addr),
        .i_calc_addr(0), .i_calc_data(0), .i_calc_we(0),
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we), .w_storage_data(w_storage_wdata), 
        .w_storage_addr(w_storage_addr), .w_storage_out(w_storage_rdata)
    );

    // =========================================================
    // 3. 辅助逻辑
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 发送一个字节到 FPGA
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx_line = 0; #(BIT_PERIOD);
            for (i=0; i<8; i=i+1) begin
                uart_rx_line = data[i]; #(BIT_PERIOD);
            end
            uart_rx_line = 1; #(BIT_PERIOD);
            #(BIT_PERIOD * 2);
        end
    endtask

    // =========================================================
    // 4. 核心测试流程
    // =========================================================
    initial begin
        rst_n = 0; uart_rx_line = 1; sw = 0; btn = 0;
        #100; rst_n = 1; #100;

        $display("=== Test Start: Display Format Check ===");

        // 1. 进入 Menu Display Mode (sw=11)
        sw = 8'b0000_0011; 
        #50; btn[0] = 1; #200; btn[0] = 0; 
        wait(w_en_input == 1);
        $display("[Time %t] Entered Menu Display Mode (Wait for Input)", $time);

        // 2. 输入维度 "2 3 "
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        #2000; // 等待分配

        // 3. 输入数据 "4 5 6 7 8 9 "
        $display("[Time %t] Sending Matrix Data...", $time);
        uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" ");
        uart_send_byte("7"); uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte(" ");
        uart_send_byte("9"); uart_send_byte(" ");

        // 4. Input 结束后，FSM 会自动跳到 DISPLAY 模式
        wait(w_en_display == 1);
        $display("[Time %t] Input Done. Display Subsystem Started!", $time);
        $display("--- Receiving UART Output from FPGA ---");

        // 接下来的输出由下方的 always 块负责解码打印
        
        wait(w_en_display == 0);
        $display("\n[Time %t] Display Complete. Test Finished.", $time);
        $stop;
    end

    // =========================================================
    // 5. UART 接收解码器 (模拟电脑接收)
    // =========================================================
    reg [7:0] rx_byte;
    integer bit_cnt;
    
    // 简单的软件 UART 接收器
    always @(negedge uart_tx_line) begin
        // 检测到起始位 (下降沿)
        #(BIT_PERIOD * 1.5); // 跳过起始位，采样第1个bit中间
        
        rx_byte = 0;
        for (bit_cnt = 0; bit_cnt < 8; bit_cnt = bit_cnt + 1) begin
            rx_byte[bit_cnt] = uart_tx_line;
            #(BIT_PERIOD);
        end
        
        // 打印接收到的字符
        // 0x0D=\r, 0x0A=\n, 0x20=Space
        if (rx_byte == 8'h0D) $write("\\r"); 
        else if (rx_byte == 8'h0A) $write("\\n\n"); // 遇到换行符多打个回车方便看
        else if (rx_byte == 8'h20) $write(" ");
        else $write("%c", rx_byte);
    end

endmodule