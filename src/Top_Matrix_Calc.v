module Top_Module (
    input wire clk,
    input wire rst_n,

    // --- 物理接口 (对应 XDC 约束) ---
    input wire uart_rx,      // 串口接收
    output wire uart_tx,     // 串口发送
    
    input wire [7:0] sw,     // 拨码开关: [7:5]运算类型, [1:0]模式选择, [3:0]倒计时设置
    input wire [4:0] btn,    // 按键: [0]确认
    output wire [7:0] led,   // LED 指示灯
    
    output wire [7:0] seg,   // 数码管段选
    output wire [3:0] an     // 数码管位选
);

    // =========================================================================
    // 1. 内部连线定义 (The Wires)
    // =========================================================================
    
    // --- FSM 信号 ---
    wire w_en_input, w_en_display, w_start_calc;
    wire w_is_gen_mode;
    wire [1:0] w_task_mode;
    wire w_addr_ready;
    wire [7:0] w_base_addr_to_input;
    wire [1:0] w_disp_mode;
    wire [7:0] w_disp_base_addr;
    wire [1:0] w_disp_total_cnt;
    wire [31:0] w_disp_m, w_disp_n;
    wire [1:0] w_disp_selected_id;
    wire [7:0] w_disp_target_addr;
    wire [2:0] w_op_code;
    wire [7:0] w_op1_addr, w_op2_addr, w_res_addr;
    
    // [关键] FSM 输出给计算器的维度信号
    wire [31:0] w_op1_m, w_op1_n, w_op2_m, w_op2_n;
    
    // FSM 状态调试信号 (用于控制数码管和定时器)
    wire [3:0] w_state; 

    // --- Input Subsystem 信号 ---
    wire w_input_rx_done;
    wire w_input_error;
    wire w_dims_valid;
    wire [31:0] w_dim_m, w_dim_n;
    wire w_id_valid;
    wire [31:0] w_input_id_val;
    
    // --- Display Subsystem 信号 ---
    wire w_disp_done;
    wire [1:0] w_disp_lut_idx_req; 
    wire [7:0] w_sys_total_cnt;    
    wire [2:0] w_sys_types_count;  

    // --- Calculator Core 信号 ---
    wire w_calc_done;
    wire [7:0] w_calc_req_addr; // 读请求
    wire [7:0] w_calc_waddr;    // 写请求
    wire [31:0] w_calc_wdata;
    wire w_calc_we;
    
    // 计算器地址合并 (读写二选一)
    wire [7:0] w_calc_addr_merged;
    assign w_calc_addr_merged = (w_calc_we) ? w_calc_waddr : w_calc_req_addr;

    // --- Storage MUX & Memory 信号 ---
    wire [7:0] w_input_addr;
    wire [31:0] w_input_data;
    wire w_input_we;
    wire [7:0] w_disp_req_addr;
    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_wdata;
    wire w_storage_we;
    wire [31:0] w_storage_rdata;

    // --- Timer & Seg7 信号 ---
    wire w_timeout;
    wire [3:0] w_timer_val;
    wire w_timer_start_pulse;
    wire w_seg_en;
    wire w_seg_mode;

    // =========================================================================
    // 2. 辅助逻辑: 定时器控制与显示模式
    // =========================================================================
    
    // 状态机状态定义 (参考 FSM)
    localparam S_CALC_START = 4'd3;  // Select OP
    localparam S_CALC_END   = 4'd11; // Res Show
    localparam S_ERROR      = 4'd15; // Error State

    // A. 生成 Timer 启动脉冲 (当 FSM 进入 S_ERROR 状态的瞬间)
    reg [3:0] state_d;
    always @(posedge clk) state_d <= w_state;
    assign w_timer_start_pulse = (w_state == S_ERROR) && (state_d != S_ERROR);

    // B. 数码管控制逻辑
    // 在计算模式(3~11) 或 错误模式(15) 时点亮
    assign w_seg_en = ((w_state >= S_CALC_START && w_state <= S_CALC_END) || (w_state == S_ERROR));
    
    // 显示模式: 1=数字(Timer) 当处于 S_ERROR; 0=符号(OpCode) 其他情况
    assign w_seg_mode = (w_state == S_ERROR) ? 1'b1 : 1'b0;

    // =========================================================================
    // 3. 模块例化
    // =========================================================================

    // --- A. 主控状态机 (Brain) ---
    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .sw(sw), .btn(btn), .led(led),
        
        // Input
        .w_dims_valid(w_dims_valid), .i_dim_m(w_dim_m), .i_dim_n(w_dim_n),
        .w_rx_done(w_input_rx_done), .w_error_flag(w_input_error),
        .i_input_id_val(w_input_id_val), .w_id_valid(w_id_valid),
        .w_en_input(w_en_input), .w_is_gen_mode(w_is_gen_mode),
        .w_task_mode(w_task_mode), .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        
        // Display
        .w_disp_done(w_disp_done), .i_disp_lut_idx_req(w_disp_lut_idx_req),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_selected_id(w_disp_selected_id),
        .w_system_total_count(w_sys_total_cnt), .w_system_types_count(w_sys_types_count),
        .w_disp_target_addr(w_disp_target_addr),
        
        // Calculator (包含维度输出)
        .w_calc_done(w_calc_done), .w_start_calc(w_start_calc),
        .w_op_code(w_op_code),
        .w_op1_addr(w_op1_addr), .w_op2_addr(w_op2_addr), .w_res_addr(w_res_addr),
        .w_op1_m(w_op1_m), .w_op1_n(w_op1_n), 
        .w_op2_m(w_op2_m), .w_op2_n(w_op2_n),
        
        .w_state(w_state) // 输出当前状态给 Top 用于控制数码管
    );

    // --- B. 输入子系统 (Ears) ---
    Input_Subsystem u_input (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
        .w_en_input(w_en_input),
        .w_base_addr(w_base_addr_to_input), .w_addr_ready(w_addr_ready),
        .w_is_gen_mode(w_is_gen_mode), .w_task_mode(w_task_mode),
        .w_input_we(w_input_we), .w_real_addr(w_input_addr), .w_input_data(w_input_data),
        .w_rx_done(w_input_rx_done), .w_error_flag(w_input_error),
        .w_dim_m(w_dim_m), .w_dim_n(w_dim_n), .w_dims_valid(w_dims_valid),
        .w_input_id_val(w_input_id_val), .w_id_valid(w_id_valid)
    );

    // --- C. 显示子系统 (Mouth) ---
    Display_Subsystem u_display (
        .clk(clk), .rst_n(rst_n),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_disp_selected_id(w_disp_selected_id),
        .i_system_total_count(w_sys_total_cnt), .i_system_types_count(w_sys_types_count),
        .o_lut_idx_req(w_disp_lut_idx_req),
        .w_storage_rdata(w_storage_rdata), .w_disp_req_addr(w_disp_req_addr),
        .uart_tx_pin(uart_tx), .w_disp_done(w_disp_done)
    );

    // --- D. 计算核心 (Muscle) ---
    Calculator_Core u_calc (
        .clk(clk), .rst_n(rst_n),
        .i_start_calc(w_start_calc), .i_op_code(w_op_code), .o_calc_done(w_calc_done),
        // 传入操作数地址和维度
        .i_op1_addr(w_op1_addr), .i_op1_m(w_op1_m), .i_op1_n(w_op1_n),
        .i_op2_addr(w_op2_addr), .i_op2_m(w_op2_m), .i_op2_n(w_op2_n),
        .i_res_addr(w_res_addr),
        // 存储交互
        .o_calc_req_addr(w_calc_req_addr), 
        .i_storage_rdata(w_storage_rdata),
        .o_calc_we(w_calc_we), .o_calc_waddr(w_calc_waddr), .o_calc_wdata(w_calc_wdata)
    );

    // --- E. 存储仲裁器 (Traffic Police) ---
    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(w_start_calc),
        // Input
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        // Display
        .i_disp_addr(w_disp_req_addr),
        // Calc (使用合并后的地址)
        .i_calc_addr(w_calc_addr_merged), 
        .i_calc_data(w_calc_wdata), 
        .i_calc_we(w_calc_we),
        // Output
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

    // --- F. 存储器 (Memory) ---
    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we),
        .w_storage_data(w_storage_wdata),
        .w_storage_addr(w_storage_addr),
        .w_storage_out(w_storage_rdata)
    );

    // --- G. 倒计时定时器 (Timer) ---
    Timer_Unit #(
        .CLK_FREQ(100_000_000)
    ) u_timer (
        .clk(clk), .rst_n(rst_n),
        .i_start_timer(w_timer_start_pulse), // 进入 ERROR 瞬间重置
        .i_en(w_state == S_ERROR),           // 在 ERROR 状态下持续运行
        .sw(sw[3:0]),                        // 假设使用开关[3:0]设定时间，或者默认10
        .w_timeout(w_timeout),
        .w_time_val(w_timer_val)
    );

    // --- H. 数码管驱动 (Face) ---
    Seg7_Driver u_seg (
        .clk(clk), .rst_n(rst_n),
        .i_en(w_seg_en),           // 仅在计算或错误时亮
        .i_disp_mode(w_seg_mode),  // 0=符号, 1=数字
        .i_op_code(w_op_code),     // 模式0数据
        .i_digit_val(w_timer_val), // 模式1数据
        .seg_data(seg),            // 输出到 FPGA 引脚
        .seg_sel(an)               // 输出到 FPGA 引脚
    );

endmodule