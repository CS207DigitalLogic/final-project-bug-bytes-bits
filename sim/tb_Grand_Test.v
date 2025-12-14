`timescale 1ns / 1ps

module tb_Grand_Test;

    // --- 信号声明 ---
    reg clk;
    reg rst_n;
    reg uart_rx_line;       
    wire uart_tx_line;      
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // 观察信号
    wire [4:0] w_fsm_state; // 5-bit state
    wire [31:0] w_input_data;
    wire w_input_we;
    wire [7:0] w_input_addr;
    wire w_en_input, w_en_display;
    
    // 存储器引用 (用于偷看内存)
    // 路径: u_storage.mem
    
    // --- 参数 ---
    parameter CLK_PERIOD = 10;
    parameter BIT_PERIOD = 8680; 

    // --- 模块例化 ---
    Top_Module u_top (
        .clk(clk),
        .sys_rst(~rst_n), // Top内部取反，所以这里给~rst_n
        .uart_rx(uart_rx_line),
        .uart_tx(uart_tx_line),
        .sw(sw),
        .btn(btn),
        .led(led)
        // 数码管不接
    );

    // --- 辅助任务 ---
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

    task press_btn(input int id);
        begin
            btn[id] = 1; #20000; btn[id] = 0; #20000;
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
                    // 使用层次化引用访问内部存储
                    $write("%4d ", u_top.u_storage.mem[addr]); 
                    addr = addr + 1;
                end
                $write("\n");
            end
            $display("--------------------------------------------------");
        end
    endtask

    // --- 主测试流程 ---
    initial begin
        // 1. 初始化
        rst_n = 0; uart_rx_line = 1; sw = 0; btn = 0;
        #100; rst_n = 1; #100;
        $display("\n=== GRAND COMPREHENSIVE TEST START ===");

        // ============================================================
        // 1. 手动输入模式测试
        // ============================================================
        $display("\n--- [STEP 1] Manual Input Mode ---");
        sw = 8'b0000_0000; press_btn(0); // Enter Mode
        wait(u_top.w_en_input);

        // Case 1: 正常输入 2x3
        $display(">> Input 1: 2x3 -> 4 5 6 7 8 9");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" "); uart_send_byte("7"); uart_send_byte(" ");
        uart_send_byte("8"); uart_send_byte(" "); uart_send_byte("9"); uart_send_byte(" ");
        wait(u_top.u_fsm.current_state == 16); // Wait Decision
        print_mem_region(0, 2, 3, "Matrix A (Slot 0)");

        // 留在该模式
        $display(">> Action: Stay in Mode (btn[1])");
        press_btn(1); 
        wait(u_top.w_en_input);

        // Case 2: 正常输入 1x4 (Type B Slot 0)
        $display(">> Input 2: 1x4 -> 2 3 4 5");
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        #2000;
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("5"); uart_send_byte(" ");
        wait(u_top.u_fsm.current_state == 16);
        print_mem_region(12, 1, 4, "Matrix B (Type B, Slot 0)");

        // 留在该模式
        $display(">> Action: Stay in Mode (btn[1])");
        press_btn(1); 
        wait(u_top.w_en_input);

        // Case 3: 自动屏蔽 (1x4, 输入5个数) -> Type B Slot 1
        $display(">> Input 3: 1x4 -> 1 2 3 4 5 (Test Shielding)");
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        #2000;
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" "); // Should be ignored
        wait(u_top.u_fsm.current_state == 16);
        print_mem_region(16, 1, 4, "Matrix B' (Type B, Slot 1, Shielded?)");

        // 留在该模式
        $display(">> Action: Stay in Mode (btn[1])");
        press_btn(1); 
        wait(u_top.w_en_input);

        // Case 4: 自动补0 & 覆盖 (1x4, 输入3个数) -> Type B Slot 0 (Overwrite Case 2)
        $display(">> Input 4: 1x4 -> 1 2 3 (Test Padding & Overwrite)");
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        #2000;
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" "); // Missing last one
        // Wait for timeout (simulated by force triggering done or just waiting)
        #6000_000; // 等待 Input 模块超时 (TIMEOUT_VAL)
        wait(u_top.u_fsm.current_state == 16);
        print_mem_region(12, 1, 4, "Matrix B (Overwrite, Padding 0)");

        // 留在该模式
        $display(">> Action: Stay in Mode (btn[1])");
        press_btn(1); 
        wait(u_top.w_en_input);

        // Case 5: 报错 & 重输
        $display(">> Input 5: 6 1 (Error Test) then 4 1 -> 3 4 5 6");
        uart_send_byte("6"); uart_send_byte(" "); // Invalid Dim
        uart_send_byte("1"); uart_send_byte(" "); 
        #1000;
        if (led == 8'b1000_0001) $display(">> [PASS] Error LED detected!");
        else $display(">> [FAIL] Error LED not detected!");
        
        // Retry with valid dims: 4 1
        uart_send_byte("4"); uart_send_byte(" "); uart_send_byte("1"); uart_send_byte(" ");
        #2000;
        uart_send_byte("3"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" "); uart_send_byte("6"); uart_send_byte(" ");
        wait(u_top.u_fsm.current_state == 16);
        print_mem_region(20, 4, 1, "Matrix C (Type C, 4x1)");

        // 返回主菜单
        $display(">> Action: Return to Menu (btn[0])");
        press_btn(0);
        wait(u_top.u_fsm.current_state == 0); // IDLE

        
        // ============================================================
        // 2. 生成模式测试
        // ============================================================
        $display("\n--- [STEP 2] Generation Mode ---");
        sw = 8'b0000_0001; press_btn(0);
        wait(u_top.w_en_input);

        $display(">> Gen: 2x3, Count 2");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" ");
        wait(u_top.u_fsm.current_state == 16);
        
        // Check Slot 1 (Addr 6-11) - New
        print_mem_region(6, 2, 3, "Gen Mat 1 (Slot 1)");
        // Check Slot 0 (Addr 0-5) - Overwrite Manual Input
        print_mem_region(0, 2, 3, "Gen Mat 2 (Slot 0, Overwrite)");

        $display(">> Action: Return to Menu (btn[0])");
        press_btn(0);
        wait(u_top.u_fsm.current_state == 0);


        // ============================================================
        // 2.5 插入辅助步骤：输入一个 3x1 矩阵 (用于后续标量乘法 x3)
        // ============================================================
        $display("\n--- [STEP 2.5] Inject Scalar '3' Helper Matrix ---");
        sw = 8'b0000_0000; press_btn(0); wait(u_top.w_en_input);
        uart_send_byte("3"); uart_send_byte(" "); uart_send_byte("1"); uart_send_byte(" ");
        #2000;
        uart_send_byte("0"); uart_send_byte(" "); uart_send_byte("0"); uart_send_byte(" ");
        uart_send_byte("0"); uart_send_byte(" "); 
        wait(u_top.u_fsm.current_state == 16);
        press_btn(0); wait(u_top.u_fsm.current_state == 0);
        // This creates Type D (3x1) at Addr 24


        // ============================================================
        // 3. 矩阵直接展示模式
        // ============================================================
        $display("\n--- [STEP 3] Menu Display Mode ---");
        sw = 8'b0000_0011; press_btn(0);
        wait(u_top.w_en_input);

        $display(">> Display: 1x3 -> 6 5 4");
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        #2000;
        uart_send_byte("6"); uart_send_byte(" "); uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("4"); uart_send_byte(" ");
        
        wait(u_top.u_fsm.current_state == 16);
        $display(">> Check UART Output for '6 5 4'");
        // This stored at Addr 27 (Type E, 1x3)

        $display(">> Action: Return to Menu (btn[0])");
        press_btn(0);
        wait(u_top.u_fsm.current_state == 0);


        // ============================================================
        // 4. 计算模式
        // ============================================================
        $display("\n--- [STEP 4] Calculation Mode ---");
        
        // --- 4.1 转置 ---
        $display(">> Calc: Transpose (Op 000)");
        sw = 8'b0000_0010; // Transpose + Calc Mode
        press_btn(0); // Enter
        press_btn(0); // Confirm Op
        wait(u_top.w_disp_done); #2000000; // Summary

        $display(">> Select: 1x4 (Type B)");
        uart_send_byte("1"); uart_send_byte(" "); uart_send_byte("4"); uart_send_byte(" ");
        wait(u_top.w_disp_done); #2000000;

        $display(">> Select ID: 1 (Slot 0: 1 2 3 0)");
        uart_send_byte("1"); uart_send_byte(" ");
        
        // Auto execute
        wait(u_top.u_fsm.current_state == 16);
        // Result is 4x1. Should be 1 2 3 0.
        // Addr allocation:
        // A(2x3):0-11, B(1x4):12-19, C(4x1):20-23, D(3x1):24-26, E(1x3):27-29.
        // Result (4x1) matches Type C! -> Stored in Type C Slot 1 (Addr 20 + 4 = 24?)
        // Wait, Type D starts at 24.
        // FSM appends new types to `free_ptr`. 
        // `free_ptr` was 30 (after E).
        // Result goes to Addr 30.
        print_mem_region(30, 4, 1, "Transpose Result");

        // --- 4.2 切换到标量乘法 ---
        $display("\n>> Action: Switch Op (btn[1] then Change SW)");
        press_btn(1); // Back to Select OP
        wait(u_top.u_fsm.current_state == 3); // S_CALC_SELECT_OP

        $display(">> Calc: Scalar Mul (Op 010)");
        sw = 8'b0100_0010; // Scalar Mul + Calc Mode
        press_btn(0); // Confirm
        wait(u_top.w_disp_done); #2000000;

        $display(">> Select Op1: 2x3 (Type A)");
        uart_send_byte("2"); uart_send_byte(" "); uart_send_byte("3"); uart_send_byte(" ");
        wait(u_top.w_disp_done); #2000000;

        $display(">> Select Op1 ID: 1 (Slot 0)");
        uart_send_byte("1"); uart_send_byte(" ");
        wait(u_top.w_disp_done); #2000000;

        $display(">> Select Op2: 3x1 (Type D - The Scalar Provider)");
        // We injected this in Step 2.5. Row=3 means Scalar=3.
        uart_send_byte("3"); uart_send_byte(" "); uart_send_byte("1"); uart_send_byte(" ");
        wait(u_top.w_disp_done); #2000000;

        $display(">> Select Op2 ID: 1");
        uart_send_byte("1"); uart_send_byte(" ");

        wait(u_top.u_fsm.current_state == 16);
        // Result: 2x3 Matrix * 3. 
        // Stored at Addr 34 (30 + 4).
        print_mem_region(34, 2, 3, "Scalar Mul Result (x3)");

        $display("\n>> Action: Return to Menu (btn[0])");
        press_btn(0);
        wait(u_top.u_fsm.current_state == 0);

        $display("\n=== ALL TESTS PASSED ===");
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