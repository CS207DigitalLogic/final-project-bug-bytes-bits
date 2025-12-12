`timescale 1ns / 1ps

module tb_Calc_Mode_Verify;

    // =========================================================
    // 1. 信号声明
    // =========================================================
    reg clk;
    reg rst_n;
    reg uart_rx_line;       // PC -> FPGA
    wire uart_tx_line;      // FPGA -> PC
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // --- 内部信号观察 ---
    wire w_en_input, w_addr_ready, w_is_gen_mode;
    wire [1:0] w_task_mode;
    wire [7:0] w_base_addr_to_input;
    
    wire w_input_we;
    wire [7:0] w_input_addr; 
    wire [31:0] w_input_data;
    
    wire w_en_display, w_disp_done;
    wire [1:0] w_disp_mode;
    wire [1:0] o_lut_idx_req; // Summary 模式用
    
    wire w_start_calc, w_calc_done;
    wire [3:0] w_fsm_state;

    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_wdata;
    wire w_storage_we;
    wire [31:0] w_storage_rdata;

    // =========================================================
    // 2. 模块例化 (集成系统)
    // =========================================================
    // FSM
    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n), .sw(sw), .btn(btn), .led(led),
        .w_en_input(w_en_input), .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        // Input Feedback
        .w_dims_valid(u_input.w_dims_valid), 
        .i_dim_m(u_input.w_dim_m), .i_dim_n(u_input.w_dim_n),
        .w_rx_done(u_input.w_rx_done), .w_error_flag(u_input.w_error_flag),
        .i_input_id_val(u_input.w_input_id_val), .w_id_valid(u_input.w_id_valid),
        // Display Control
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_base_addr(u_disp.w_disp_base_addr), .w_disp_total_cnt(u_disp.w_disp_total_cnt),
        .w_disp_m(u_disp.w_disp_m), .w_disp_n(u_disp.w_disp_n),
        .w_disp_selected_id(u_disp.w_disp_selected_id),
        .w_disp_done(w_disp_done),
        .i_disp_lut_idx_req(o_lut_idx_req),
        .w_system_total_count(u_disp.i_system_total_count), 
        .w_system_types_count(u_disp.i_system_types_count),
        // Calc Control
        .w_start_calc(w_start_calc), .w_calc_done(w_calc_done),
        .w_op_code(u_calc.i_op_code),
        .w_op1_addr(u_calc.i_op1_addr), .w_op1_m(u_calc.i_op1_m), .w_op1_n(u_calc.i_op1_n),
        .w_op2_addr(u_calc.i_op2_addr), .w_op2_m(u_calc.i_op2_m), .w_op2_n(u_calc.i_op2_n),
        .w_res_addr(u_calc.i_res_addr),
        .w_state(w_fsm_state)
    );

    // Input
    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr_to_input), .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_input_we(w_input_we), .w_real_addr(w_input_addr), .w_input_data(w_input_data)
        // 其他反馈信号在上接 FSM
    );

    // Display
    Display_Subsystem u_disp (
        .clk(clk), .rst_n(rst_n),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .o_lut_idx_req(o_lut_idx_req),
        .w_storage_rdata(w_storage_rdata), .w_disp_req_addr(u_disp.w_disp_req_addr),
        .uart_tx_pin(uart_tx_line), .w_disp_done(w_disp_done)
        // 其他信号已连接
    );

    // Calc
    // 地址合并逻辑
    wire [7:0] w_calc_addr_merged = (u_calc.o_calc_we) ? u_calc.o_calc_waddr : u_calc.o_calc_req_addr;
    Calculator_Core u_calc (
        .clk(clk), .rst_n(rst_n),
        .i_start_calc(w_start_calc), .o_calc_done(w_calc_done),
        .i_storage_rdata(w_storage_rdata)
        // 其他信号已连接
    );

    // Mux
    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(w_start_calc),
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        .i_disp_addr(u_disp.w_disp_req_addr),
        .i_calc_addr(w_calc_addr_merged), .i_calc_data(u_calc.o_calc_wdata), .i_calc_we(u_calc.o_calc_we),
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

    // Storage
    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we), .w_storage_data(w_storage_wdata), 
        .w_storage_addr(w_storage_addr), .w_storage_out(w_storage_rdata)
    );

    // =========================================================
    // 3. 辅助任务
    // =========================================================
    parameter CLK_PERIOD = 10;
    parameter BIT_PERIOD = 8680;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // UART 发送
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

    // 【新增】打印内存区域任务 (God View)
    task print_mem_region;
        input [7:0] start_addr;
        input integer rows;
        input integer cols;
        input [8*20:1] name; // 20 chars max
        integer r, c;
        reg [7:0] addr;
        begin
            $display("--------------------------------------------------");
            $display(" [MEMORY PEEK] %0s (Addr %0d - %0d)", name, start_addr, start_addr + rows*cols - 1);
            addr = start_addr;
            for (r = 0; r < rows; r = r + 1) begin
                $write("   Row %0d: ", r);
                for (c = 0; c < cols; c = c + 1) begin
                    $write("%4d ", u_storage.mem[addr]); // 直接读 Storage 内部 mem 数组
                    addr = addr + 1;
                end
                $write("\n");
            end
            $display("--------------------------------------------------");
        end
    endtask

    // =========================================================
    // 4. 测试流程
    // =========================================================
    initial begin
        rst_n = 0; uart_rx_line = 1; sw = 0; btn = 0;
        #100; rst_n = 1; #100;

        // --- Step 1: Input A (2x3) ---
        $display("\n=== [STEP 1] Input Matrix A (2x3) ===");
        sw = 0; btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" "); uart_send_byte("7"); uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte(" "); uart_send_byte("9"); uart_send_byte(" ");
        wait(!w_en_input);

        // 偷看内存：A 应该在地址 0
        print_mem_region(0, 2, 3, "Matrix A (Slot 0)");


        // --- Step 2: Input B (2x2) ---
        $display("\n=== [STEP 2] Input Matrix B (2x2) ===");
        btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        #2000;
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" "); uart_send_byte("1"); uart_send_byte(" ");
        wait(!w_en_input);

        // 偷看内存：B 应该在地址 12 (因为 2x3 占了 0-5, Slot 1 占 6-11, 所以新 Type 从 12 开始)
        print_mem_region(12, 2, 2, "Matrix B (New Type)");


        // --- Step 3: Generate C (2x3, Count 2) ---
        $display("\n=== [STEP 3] Generate C (2x3, Count=2) ===");
        sw = 8'b0000_0001; // Gen Mode
        btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" "); // Count = 2
        wait(!w_en_input);

        // 偷看内存：
        // C1 应该在 Slot 1 (地址 6-11)
        // C2 应该在 Slot 0 (地址 0-5)，此时应该已经覆盖了 A
        $display(">>> Check Generation & Overwrite:");
        print_mem_region(6, 2, 3, "Matrix C1 (Slot 1)");
        print_mem_region(0, 2, 3, "Matrix C2 (Slot 0)");


        // --- Step 4: Calculator Mode ---
        $display("\n=== [STEP 4] Calculator Mode (Addition) ===");
        sw = 8'b0010_0010; // Add + Calc Mode
        
        // 1. Enter Mode
        btn[0] = 1; #50; btn[0] = 0; #200;
        // 2. Confirm Op
        btn[0] = 1; #50; btn[0] = 0;
        
        wait(u_disp.w_disp_mode == 2);
        wait(u_disp.w_disp_done);
        $display(">> Summary Shown. (Check UART for '3 2*3*2 ...')");

        // Filter: Select 2x3
        wait(w_en_input);
        $display(">> Input Filter Dimensions: 2 3");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        
        wait(u_disp.w_disp_mode == 1);
        wait(u_disp.w_disp_done);
        $display(">> List Shown. (Check UART for ID list)");

        // Select ID 1 (C2 - Overwrite)
        wait(w_en_input);
        $display(">> Select Operand 1: ID 1 (Target: C2 @ Slot 0)");
        uart_send_byte("1"); uart_send_byte(" ");
        
        wait(u_disp.w_disp_mode == 3);
        wait(u_disp.w_disp_done); // 等待显示完成

        // Select ID 2 (C1)
        wait(w_en_input);
        $display(">> Select Operand 2: ID 2 (Target: C1 @ Slot 1)");
        uart_send_byte("2"); uart_send_byte(" ");
        
        wait(u_disp.w_disp_mode == 3);
        // 这里增加足够延时，确保 UART 发完
        #500_000; 
        
        $display("\n=== Test Finished ===");
        $stop;
    end

    // =========================================================
    // 5. UART 接收并美化输出
    // =========================================================
    reg [7:0] rx_byte;
    integer bit_cnt;
    
    // 独立的 UART 监听进程
    always @(negedge uart_tx_line) begin
        #(BIT_PERIOD * 1.5);
        rx_byte = 0;
        for (bit_cnt = 0; bit_cnt < 8; bit_cnt = bit_cnt + 1) begin
            rx_byte[bit_cnt] = uart_tx_line;
            #(BIT_PERIOD);
        end
        
        // 美化打印逻辑
        if (rx_byte == 8'h0D) begin
            // 忽略单纯的 CR，避免回车覆盖日志
        end
        else if (rx_byte == 8'h0A) begin
            $write("\n[FPGA UART] "); // 换行后加前缀
        end
        else if (rx_byte == 8'h20) begin
            $write(" ");
        end
        else begin
            $write("%c", rx_byte);
        end
    end

endmodule