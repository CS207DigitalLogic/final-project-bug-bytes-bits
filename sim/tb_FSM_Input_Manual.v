`timescale 1ns / 1ps

module tb_FSM_Input_Manual;

    // =========================================================
    // 1. 信号定义
    // =========================================================
    reg clk;
    reg rst_n;
    
    // 模拟物理输入
    reg uart_rx_line;
    reg [7:0] sw;
    reg [4:0] btn;
    wire [7:0] led;

    // 内部连线 (观察用)
    wire w_en_input;
    wire [7:0] w_base_addr_to_input;
    wire w_addr_ready;
    wire [31:0] w_input_data;
    wire w_input_we;
    wire [7:0] w_input_addr;
    wire [31:0] w_storage_rdata;
    
    // FSM 状态观测
    wire [3:0] w_fsm_state;

    // 参数
    parameter CLK_FREQ = 100_000_000;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 8680; // 10^9 / 115200
    parameter CLK_PERIOD = 10;

    // =========================================================
    // 2. 模块例化 (最小系统：FSM + Input + Mux + Storage)
    // =========================================================

    // 1. FSM Controller
    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .sw(sw), .btn(btn), .led(led),
        
        // Input 交互
        .w_en_input(w_en_input), 
        .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        
        // 这里的 Input 反馈信号由下方的 u_input 产生并连接
        .w_dims_valid(u_input.w_dims_valid), 
        .i_dim_m(u_input.w_dim_m), 
        .i_dim_n(u_input.w_dim_n),
        .w_rx_done(u_input.w_rx_done), 
        .w_error_flag(u_input.w_error_flag),
        .i_input_id_val(u_input.w_input_id_val), 
        .w_id_valid(u_input.w_id_valid),
        
        // 其他不测的接口置 0 或悬空
        .w_disp_done(0), .w_calc_done(0),
        .w_state(w_fsm_state)
    );

    // 2. Input Subsystem
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

    // 3. Storage MUX
    // (为了测试简单，这里只接 Input 通道，其他通道给 0)
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

    // 4. Matrix Storage
    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we),
        .w_storage_data(w_storage_wdata),
        .w_storage_addr(w_storage_addr),
        .w_storage_out(w_storage_rdata)
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
    // 4. 主测试流程
    // =========================================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        uart_rx_line = 1;
        sw = 0; btn = 0;

        // --- 复位释放 ---
        #100; rst_n = 1; #100;

        $display("=== Test: FSM Manual Input Mode ===");

        // 1. 进入输入模式
        // sw[1:0] = 00 (Input Mode)
        sw = 8'b0000_0000; 
        #50;
        // 按下确认键 (模拟人手按下约 200ns)
        btn[0] = 1; #200; btn[0] = 0; 
        
        // 等待 FSM 反应
        wait(w_en_input == 1);
        $display("[Time %t] FSM State: %d (Should be 1/INPUT)", $time, w_fsm_state);

        // 2. 发送维度 "2 3 "
        $display("[Time %t] Sending Dimensions '2 3'...", $time);
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        
        // FSM 应该会自动分配地址 0，并拉高 w_addr_ready
        // 我们等 Input 模块开始写数据 (w_input_we) 来确认握手成功
        
        // 3. 发送数据 "1 2 3 4 5 6 "
        // 注意：Input 模块会先预清零，然后才写真数据，所以中间会有延迟
        // 为了确保维度解析后的握手完成，我们稍微等一下再发数据
        #2000; 
        $display("[Time %t] Sending Data '1 2 3 4 5 6'...", $time);
        uart_send_byte("1"); uart_send_byte(" ");
        uart_send_byte("2"); uart_send_byte(" ");
        uart_send_byte("3"); uart_send_byte(" ");
        uart_send_byte("4"); uart_send_byte(" ");
        uart_send_byte("5"); uart_send_byte(" ");
        uart_send_byte("6"); uart_send_byte(" "); // 结束符触发完成

        // 4. 等待 FSM 处理完成
        wait(w_en_input == 0); // FSM 应该自动回到 IDLE
        $display("[Time %t] FSM returned to IDLE. Input Complete.", $time);

        // 5. 核对存储器内容
        #100;
        $display("--- Checking Memory Content ---");
        if (u_storage.mem[0] === 1) $display("Addr 0: 1 [PASS]"); else $display("Addr 0: %d [FAIL]", u_storage.mem[0]);
        if (u_storage.mem[1] === 2) $display("Addr 1: 2 [PASS]"); else $display("Addr 1: %d [FAIL]", u_storage.mem[1]);
        if (u_storage.mem[2] === 3) $display("Addr 2: 3 [PASS]"); else $display("Addr 2: %d [FAIL]", u_storage.mem[2]);
        if (u_storage.mem[3] === 4) $display("Addr 3: 4 [PASS]"); else $display("Addr 3: %d [FAIL]", u_storage.mem[3]);
        if (u_storage.mem[4] === 5) $display("Addr 4: 5 [PASS]"); else $display("Addr 4: %d [FAIL]", u_storage.mem[4]);
        if (u_storage.mem[5] === 6) $display("Addr 5: 6 [PASS]"); else $display("Addr 5: %d [FAIL]", u_storage.mem[5]);

        $stop;
    end

    // 实时监控
    always @(posedge clk) begin
        if (w_storage_we) begin
            $display("[WRITE] Time: %t, Addr: %d, Data: %d", $time, w_storage_addr, w_storage_wdata);
        end
    end

endmodule