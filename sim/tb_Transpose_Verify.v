`timescale 1ns / 1ps

module tb_Transpose_Verify;

    // =========================================================
    // 1. 信号声明
    // =========================================================
    reg clk;
    reg rst_n;
    reg uart_rx_line;       
    wire uart_tx_line;      
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // UART 接收变量
    reg [7:0] rx_byte;
    integer bit_cnt;

    // --- 内部信号 ---
    wire w_en_input, w_addr_ready, w_is_gen_mode;
    wire [1:0] w_task_mode;
    wire [7:0] w_base_addr_to_input;
    wire w_input_we;
    wire [7:0] w_input_addr; 
    wire [31:0] w_input_data;
    wire w_rx_done, w_error_flag, w_dims_valid, w_id_valid;
    wire [31:0] w_dim_m, w_dim_n, w_input_id_val;

    wire w_en_display, w_disp_done;
    wire [1:0] w_disp_mode;
    wire [7:0] w_disp_base_addr, w_disp_req_addr;
    wire [1:0] w_disp_total_cnt, w_disp_selected_id;
    wire [31:0] w_disp_m, w_disp_n;
    wire [1:0] o_lut_idx_req;
    wire [7:0] i_system_total_count;
    wire [2:0] i_system_types_count;

    wire w_start_calc, w_calc_done;
    wire [2:0] w_op_code;
    wire [7:0] w_op1_addr, w_op2_addr, w_res_addr;
    wire [31:0] w_op1_m, w_op1_n, w_op2_m, w_op2_n;
    
    wire [7:0] w_calc_req_addr, w_calc_waddr;
    wire [31:0] w_calc_wdata;
    wire w_calc_we;
    wire [3:0] w_fsm_state;

    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_wdata, w_storage_rdata;
    wire w_storage_we;
    
    wire [7:0] w_calc_addr_merged;
    assign w_calc_addr_merged = (w_calc_we) ? w_calc_waddr : w_calc_req_addr;

    // =========================================================
    // 2. 模块例化
    // =========================================================
    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n), .sw(sw), .btn(btn), .led(led),
        .w_en_input(w_en_input), .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_dims_valid(w_dims_valid), .i_dim_m(w_dim_m), .i_dim_n(w_dim_n),
        .w_rx_done(w_rx_done), .w_error_flag(w_error_flag),
        .i_input_id_val(w_input_id_val), .w_id_valid(w_id_valid),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_selected_id(w_disp_selected_id),
        .w_disp_done(w_disp_done),
        .i_disp_lut_idx_req(o_lut_idx_req),
        .w_system_total_count(i_system_total_count), .w_system_types_count(i_system_types_count),
        .w_start_calc(w_start_calc), .w_calc_done(w_calc_done),
        .w_op_code(w_op_code),
        .w_op1_addr(w_op1_addr), .w_op1_m(w_op1_m), .w_op1_n(w_op1_n),
        .w_op2_addr(w_op2_addr), .w_op2_m(w_op2_m), .w_op2_n(w_op2_n),
        .w_res_addr(w_res_addr),
        .w_state(w_fsm_state)
    );

    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx_line),
        .w_en_input(w_en_input), .w_base_addr(w_base_addr_to_input), .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_input_we(w_input_we), .w_real_addr(w_input_addr), .w_input_data(w_input_data),
        .w_rx_done(w_rx_done), .w_error_flag(w_error_flag),
        .w_dims_valid(w_dims_valid), .w_dim_m(w_dim_m), .w_dim_n(w_dim_n),
        .w_input_id_val(w_input_id_val), .w_id_valid(w_id_valid)
    );

    Display_Subsystem u_disp (
        .clk(clk), .rst_n(rst_n),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_disp_selected_id(w_disp_selected_id),
        .i_system_total_count(i_system_total_count), .i_system_types_count(i_system_types_count),
        .o_lut_idx_req(o_lut_idx_req),
        .w_storage_rdata(w_storage_rdata), .w_disp_req_addr(w_disp_req_addr),
        .uart_tx_pin(uart_tx_line), .w_disp_done(w_disp_done)
    );

    Calculator_Core u_calc (
        .clk(clk), .rst_n(rst_n),
        .i_start_calc(w_start_calc), .o_calc_done(w_calc_done),
        .i_op_code(w_op_code),
        .i_op1_addr(w_op1_addr), .i_op1_m(w_op1_m), .i_op1_n(w_op1_n),
        .i_op2_addr(w_op2_addr), .i_op2_m(w_op2_m), .i_op2_n(w_op2_n),
        .i_res_addr(w_res_addr),
        .o_calc_req_addr(w_calc_req_addr), .i_storage_rdata(w_storage_rdata),
        .o_calc_we(w_calc_we), .o_calc_waddr(w_calc_waddr), .o_calc_wdata(w_calc_wdata)
    );

    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(w_start_calc),
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        .i_disp_addr(w_disp_req_addr),
        .i_calc_addr(w_calc_addr_merged), .i_calc_data(w_calc_wdata), .i_calc_we(w_calc_we),
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

    Matrix_storage u_storage (
        .clk(clk), .w_storage_we(w_storage_we), .w_storage_data(w_storage_wdata), 
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
            for (i=0; i<8; i=i+1) begin uart_rx_line = data[i]; #(BIT_PERIOD); end
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
            $display(" [MEMORY] %0s (Start Addr: %0d)", name, start_addr);
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
    // 4. 主测试流程
    // =========================================================
    initial begin
        rst_n = 0; uart_rx_line = 1; sw = 0; btn = 0;
        #100; rst_n = 1; #100;

        // --- Step 1: Input A (2x3) ---
        $display("\n=== [STEP 1] Input Matrix A (2x3) ===");
        // Sw=00 (Input Mode)
        sw = 0; btn[0] = 1; #50; btn[0] = 0; 
        wait(w_en_input);
        
        // Dims: 2 3
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        // Data: 1 2 3 / 4 5 6
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" "); uart_send_byte("6"); uart_send_byte(" ");
        wait(!w_en_input);

        print_mem_region(0, 2, 3, "Matrix A");

        // --- Step 2: Calc Transpose (A^T) ---
        $display("\n=== [STEP 2] Calc: Transpose (A^T) ===");
        // sw[7:5] = 000 (Transpose)
        // sw[1:0] = 10 (Calc Mode)
        // -> 0000_0010 = 0x02
        sw = 8'b0000_0010; 
        
        // 1. Enter Mode
        btn[0] = 1; #50; btn[0] = 0; #200;
        
        // 2. Confirm Op
        btn[0] = 1; #50; btn[0] = 0;
        
        // Wait Summary
        wait(u_disp.w_disp_done); #2000000; 
        $display(">> Summary Shown.");

        // 3. Select Op1 Dims: 2x3
        wait(w_en_input);
        $display(">> Filter Op1: 2x3");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000; // List Shown

        // 4. Select Op1 ID: 1
        wait(w_en_input);
        $display(">> Select Op1 ID: 1");
        uart_send_byte("1"); uart_send_byte(" ");
        wait(u_disp.w_disp_done); #2000000; // Op1 Shown

        // 5. Automatic Execution (No Op2 needed)
        // FSM should jump directly to Execution after showing Op1
        $display(">> Calculating (Auto-start)...");
        
        wait(u_disp.w_disp_mode == 0); // Result Mode
        wait(u_disp.w_disp_done); 
        #3000000;
        $display(">> Result Displayed.");

        // ----------------------------------------------------------------
        // [STEP 3] Verify Result
        // ----------------------------------------------------------------
        // A (2x3) takes 0-5. Slot 1 takes 6-11.
        // Result (3x2) is New Type -> Starts at 12.
        print_mem_region(12, 3, 2, "Result Matrix (A^T)");

        $display("\n=== Test Finished ===");
        $stop;
    end

    // UART Print
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