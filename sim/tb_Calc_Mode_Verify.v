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

    // --- 内部信号 ---
    wire w_en_input, w_addr_ready, w_is_gen_mode;
    wire [1:0] w_task_mode;
    wire [7:0] w_base_addr_to_input;
    wire w_input_we;
    wire [7:0] w_input_addr; 
    wire [31:0] w_input_data;
    wire w_en_display, w_disp_done;
    wire [1:0] w_disp_mode;
    wire [1:0] o_lut_idx_req; 
    wire w_start_calc, w_calc_done;
    wire [3:0] w_fsm_state;
    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_wdata;
    wire w_storage_we;
    wire [31:0] w_storage_rdata;

    // =========================================================
    // 2. 模块例化
    // =========================================================
    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n), .sw(sw), .btn(btn), .led(led),
        .w_en_input(w_en_input), .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_dims_valid(u_input.w_dims_valid), 
        .i_dim_m(u_input.w_dim_m), .i_dim_n(u_input.w_dim_n),
        .w_rx_done(u_input.w_rx_done), .w_error_flag(u_input.w_error_flag),
        .i_input_id_val(u_input.w_input_id_val), .w_id_valid(u_input.w_id_valid),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_base_addr(u_disp.w_disp_base_addr), .w_disp_total_cnt(u_disp.w_disp_total_cnt),
        .w_disp_m(u_disp.w_disp_m), .w_disp_n(u_disp.w_disp_n),
        .w_disp_selected_id(u_disp.w_disp_selected_id),
        .w_disp_done(w_disp_done),
        .i_disp_lut_idx_req(o_lut_idx_req),
        .w_system_total_count(u_disp.i_system_total_count), 
        .w_system_types_count(u_disp.i_system_types_count),
        .w_start_calc(w_start_calc), .w_calc_done(w_calc_done),
        .w_op_code(u_calc.i_op_code),
        .w_op1_addr(u_calc.i_op1_addr), .w_op1_m(u_calc.i_op1_m), .w_op1_n(u_calc.i_op1_n),
        .w_op2_addr(u_calc.i_op2_addr), .w_op2_m(u_calc.i_op2_m), .w_op2_n(u_calc.i_op2_n),
        .w_res_addr(u_calc.i_res_addr),
        .w_state(w_fsm_state)
    );

    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr_to_input), .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_input_we(w_input_we), .w_real_addr(w_input_addr), .w_input_data(w_input_data)
    );

    Display_Subsystem u_disp (
        .clk(clk), .rst_n(rst_n),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .o_lut_idx_req(o_lut_idx_req),
        .w_storage_rdata(w_storage_rdata), .w_disp_req_addr(u_disp.w_disp_req_addr),
        .uart_tx_pin(uart_tx_line), .w_disp_done(w_disp_done)
    );

    wire [7:0] w_calc_addr_merged = (u_calc.o_calc_we) ? u_calc.o_calc_waddr : u_calc.o_calc_req_addr;
    Calculator_Core u_calc (
        .clk(clk), .rst_n(rst_n),
        .i_start_calc(w_start_calc), .o_calc_done(w_calc_done),
        .i_storage_rdata(w_storage_rdata)
    );

    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(w_start_calc),
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        .i_disp_addr(u_disp.w_disp_req_addr),
        .i_calc_addr(w_calc_addr_merged), .i_calc_data(u_calc.o_calc_wdata), .i_calc_we(u_calc.o_calc_we),
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

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

    task print_mem_region;
        input [7:0] start_addr;
        input integer rows;
        input integer cols;
        input [8*40:1] name; 
        integer r, c;
        reg [7:0] addr;
        begin
            $display("--------------------------------------------------");
            $display(" [MEMORY] %0s (Addr %0d)", name, start_addr);
            addr = start_addr;
            for (r = 0; r < rows; r = r + 1) begin
                $write("   Row %0d: ", r);
                for (c = 0; c < cols; c = c + 1) begin
                    $write("%4d ", u_storage.mem[addr]); 
                    addr = addr + 1;
                end
                $write("\n");
            end
            $display("--------------------------------------------------");
        end
    endtask

    // =========================================================
    // 4. 测试主流程
    // =========================================================
    initial begin
        rst_n = 0; uart_rx_line = 1; sw = 0; btn = 0;
        #100; rst_n = 1; #100;

        // --- Step 1: Input A (2x3) ---
        $display("\n=== [STEP 1] Input Matrix A (2x3) ===");
        sw = 0; btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        // Data: 4 5 6 / 7 8 9
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" "); uart_send_byte("7"); uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte(" "); uart_send_byte("9"); uart_send_byte(" ");
        wait(!w_en_input);
        print_mem_region(0, 2, 3, "Matrix A (Slot 0)");

        // --- Step 2: Input B (2x2) ---
        $display("\n=== [STEP 2] Input Matrix B (2x2) ===");
        btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        #2000;
        // Data: 4 2 / 5 1
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" "); uart_send_byte("1"); uart_send_byte(" ");
        wait(!w_en_input);
        print_mem_region(12, 2, 2, "Matrix B (New Type)");

        // --- Step 3: Generate C (Overwrite A) ---
        $display("\n=== [STEP 3] Generate C (Overwrite) ===");
        sw = 8'b0000_0001; 
        btn[0] = 1; #50; btn[0] = 0; wait(w_en_input);
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" "); 
        wait(!w_en_input);
        print_mem_region(0, 2, 3, "Matrix C2 (Slot 0, Overwrite A)");

        // --- Step 4: Addition (C1 + C2) ---
        $display("\n=== [STEP 4] Calc: Addition (C1 + C2) ===");
        sw = 8'b0010_0010; // OpCode 001 (Add)
        
        // 1. Enter Mode & Confirm
        btn[0] = 1; #50; btn[0] = 0; #200;
        btn[0] = 1; #50; btn[0] = 0;
        
        wait(u_disp.w_disp_done); #2000000; // Summary Shown

        // 2. Select Op 1 Dim (2x3)
        wait(w_en_input);
        $display(">> Input Op1 Dims: 2 3");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000; // List Shown

        // 3. Select Op 1 ID (1)
        wait(w_en_input);
        $display(">> Input Op1 ID: 1");
        uart_send_byte("1"); uart_send_byte(" ");
        wait(u_disp.w_disp_mode == 3); // Wait for Show
        wait(u_disp.w_disp_done); #2000000; // Op1 Shown

        // 【关键修复】4. Select Op 2 Dim (2x3) - 之前漏了这步！
        wait(w_en_input);
        $display(">> Input Op2 Dims: 2 3 (Required by FSM)");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000; // List Shown again

        // 5. Select Op 2 ID (2)
        wait(w_en_input);
        $display(">> Input Op2 ID: 2");
        uart_send_byte("2"); uart_send_byte(" ");
        wait(u_disp.w_disp_mode == 3);
        wait(u_disp.w_disp_done); #2000000; // Op2 Shown

        // 6. Check Result
        wait(u_disp.w_disp_mode == 0); // Result Mode
        wait(u_disp.w_disp_done); #2000000;
        print_mem_region(20, 2, 3, "Addition Result");

        // --- Step 5: Multiplication (B x B) ---
        $display("\n=== [STEP 5] Calc: Mult (B x B) ===");
        sw = 8'b0110_0010; // OpCode 011 (Mat Mult)
        #200;
        btn[0] = 1; #50; btn[0] = 0; #200; // Enter
        btn[0] = 1; #50; btn[0] = 0;       // Confirm

        wait(u_disp.w_disp_done); #2000000; // Summary

        // 1. Select Op 1 Dim (2x2)
        wait(w_en_input);
        $display(">> Input Op1 Dims: 2 2");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000;

        // 2. Select Op 1 ID (1 - Matrix B)
        wait(w_en_input);
        $display(">> Input Op1 ID: 1");
        uart_send_byte("1"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000;

        // 3. Select Op 2 Dim (2x2)
        wait(w_en_input);
        $display(">> Input Op2 Dims: 2 2");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000;

        // 4. Select Op 2 ID (1 - Matrix B again)
        wait(w_en_input);
        $display(">> Input Op2 ID: 1");
        uart_send_byte("1"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000;

        // 5. Check Result
        wait(u_disp.w_disp_mode == 0);
        wait(u_disp.w_disp_done); #2000000;
        
        // Add Result (6 words) + Mult Result (4 words). 20 + 6 = 26.
        print_mem_region(26, 2, 2, "Mult Result (B*B)");

        $display("\n=== Test Finished ===");
        $stop;
    end

    // UART Print
    reg [7:0] rx_byte;
    integer bit_cnt;
    always @(negedge uart_tx_line) begin
        #(BIT_PERIOD * 1.5);
        rx_byte = 0;
        for (bit_cnt = 0; bit_cnt < 8; bit_cnt = bit_cnt + 1) begin
            rx_byte[bit_cnt] = uart_tx_line;
            #(BIT_PERIOD);
        end
        if (rx_byte == 8'h0D) begin end
        else if (rx_byte == 8'h0A) $write("\n[FPGA UART] ");
        else if (rx_byte == 8'h20) $write(" ");
        else $write("%c", rx_byte);
    end

endmodule