`timescale 1ns / 1ps

module tb_Multi_Input_Test;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    reg clk;
    reg rst_n;
    
    // 物理接口模拟
    reg uart_rx_line;
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // 内部连接线
    wire w_en_input;
    wire [7:0] w_base_addr_to_input;
    wire w_addr_ready;
    wire [31:0] w_input_data;
    wire w_input_we;
    wire [7:0] w_input_addr;
    wire [31:0] w_storage_rdata;
    
    // FSM 状态
    wire [3:0] w_fsm_state;

    // 参数
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 8680; 
    parameter CLK_PERIOD = 10;

    // =========================================================
    // 2. 模块例化 (System Integration)
    // =========================================================

    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .sw(sw), .btn(btn), .led(led),
        
        .w_en_input(w_en_input), 
        .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        
        .w_dims_valid(u_input.w_dims_valid), 
        .i_dim_m(u_input.w_dim_m), 
        .i_dim_n(u_input.w_dim_n),
        .w_rx_done(u_input.w_rx_done), 
        .w_error_flag(u_input.w_error_flag),
        .i_input_id_val(u_input.w_input_id_val), 
        .w_id_valid(u_input.w_id_valid),
        
        .w_disp_done(0), .w_calc_done(0),
        .w_state(w_fsm_state)
    );

    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr_to_input), 
        .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(u_fsm.w_is_gen_mode), 
        .w_task_mode(u_fsm.w_task_mode),
        
        .w_input_we(w_input_we), 
        .w_real_addr(w_input_addr), 
        .w_input_data(w_input_data)
    );

    // MUX 只接 Input
    wire w_storage_we;
    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_wdata;

    Storage_Mux u_mux (
        .i_en_input(w_en_input), 
        .i_en_display(0), .i_en_calc(0),
        .i_input_addr(w_input_addr), 
        .i_input_data(w_input_data), 
        .i_input_we(w_input_we),
        .i_disp_addr(0), .i_calc_addr(0), .i_calc_data(0), .i_calc_we(0),
        .o_storage_addr(w_storage_addr), 
        .o_storage_data(w_storage_wdata), 
        .o_storage_we(w_storage_we)
    );

    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we),
        .w_storage_data(w_storage_wdata),
        .w_storage_addr(w_storage_addr),
        .w_storage_out(w_storage_rdata)
    );

    // =========================================================
    // 3. 驱动逻辑
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

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
    // 4. 测试主流程
    // =========================================================
    initial begin
        rst_n = 0;
        uart_rx_line = 1;
        sw = 0; btn = 0;
        #100; rst_n = 1; #100;

        $display("=== Test Start: Multi-Input Logic ===");

        // --- 1. 进入输入模式 ---
        sw = 8'b0000_0000; 
        #50; btn[0] = 1; #200; btn[0] = 0; 
        wait(w_en_input == 1);
        $display("[Time %t] Entered Input Mode.", $time);

        // --- 2. 输入矩阵 A (2x2) -> 预期地址 0 ---
        $display("[STEP 1] Sending Matrix A (2x2)...");
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" ");
        // 等待握手...
        #2000; 
        // 数据全是 1
        uart_send_byte("1"); uart_send_byte(" ");
        uart_send_byte("1"); uart_send_byte(" ");
        uart_send_byte("1"); uart_send_byte(" ");
        uart_send_byte("1"); uart_send_byte(" "); 
        
        // 等待 Input 结束
        wait(w_en_input == 0);
        $display("[STEP 1] Matrix A Complete. FSM returned to IDLE.");
        #1000;

        // --- 3. 重新进入模式，输入矩阵 B (2x3) -> 预期地址 8 ---
        btn[0] = 1; #200; btn[0] = 0; 
        wait(w_en_input == 1);
        $display("[STEP 2] Sending Matrix B (2x3)...");
        
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        // 数据全是 2
        repeat(6) begin
            uart_send_byte("2"); uart_send_byte(" ");
        end
        
        wait(w_en_input == 0);
        $display("[STEP 2] Matrix B Complete.");
        #1000;

        // --- 4. 重新进入模式，输入矩阵 C (2x2) -> 预期地址 4 (Ping-Pong) ---
        btn[0] = 1; #200; btn[0] = 0; 
        wait(w_en_input == 1);
        $display("[STEP 3] Sending Matrix C (2x2) - SAME DIM AS A...");
        
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" ");
        #2000;
        // 数据全是 3
        uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        
        wait(w_en_input == 0);
        $display("[STEP 3] Matrix C Complete. Starting Memory Check...");
        
        // --- 5. 最终内存核验 ---
        #100;
        
        // 检查 Slot 0 (Addr 0-3): 应该是 1 (Matrix A)
        if (u_storage.mem[0]===1 && u_storage.mem[3]===1) $display("Slot 0 (Addr 0-3): Matrix A [PASS]");
        else $display("Slot 0 (Addr 0-3): FAIL. Data: %d", u_storage.mem[0]);

        // 检查 Slot 1 (Addr 4-7): 应该是 3 (Matrix C, Ping-Pong 到了这里)
        if (u_storage.mem[4]===3 && u_storage.mem[7]===3) $display("Slot 1 (Addr 4-7): Matrix C [PASS]");
        else $display("Slot 1 (Addr 4-7): FAIL. Data: %d (Should be 3)", u_storage.mem[4]);

        // 检查 New Type (Addr 8-13): 应该是 2 (Matrix B)
        // 注意：2x2 占用了 0~3 和 4~7，总共 8 个位置，所以 B 从 8 开始
        if (u_storage.mem[8]===2 && u_storage.mem[13]===2) $display("New Type (Addr 8-13): Matrix B [PASS]");
        else $display("New Type (Addr 8-13): FAIL. Data: %d", u_storage.mem[8]);

        $stop;
    end

endmodule