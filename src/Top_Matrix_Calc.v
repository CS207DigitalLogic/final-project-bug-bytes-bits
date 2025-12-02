module Top_Matrix_Calc (
    input wire clk,       // 系统时钟 (100MHz)
    input wire rst_n,     // 复位按钮 (低电平有效)
    
    // 1. 物理通信接口
    input wire uart_rx,   // 串口接收 (连接 USB-UART RX)
    output wire uart_tx,  // 串口发送 (连接 USB-UART TX)

    // 2. 物理人机交互接口
    input wire [7:0] sw,  // 拨动开关 (选择模式、参数)
    input wire [4:0] btn, // 按键 (btn[0]确认, btn[1]复位...)
    
    output wire [7:0] led,      // LED 指示灯 (报错用)
    output wire [7:0] seg_sel,  // 数码管位选
    output wire [7:0] seg_data  // 数码管段选
);

    // ============================================================
    // 1. 内部信号定义 (Internal Wires)
    // ============================================================
    
    // --- FSM 控制信号 ---
    wire [3:0] w_state;       // 当前状态 (控制 MUX)
    wire w_en_input;          // 启动输入
    wire w_start_calc;        // 启动计算
    wire w_start_disp;        // 启动显示
    wire w_start_timer;       // 启动倒计时
    wire [2:0] w_op_code;     // 运算类型码
    
    // --- 状态反馈信号 (Flags) ---
    wire w_rx_done;           // 输入完成
    wire w_error_flag;        // 输入错误
    wire w_calc_done;         // 计算完成
    wire w_disp_done;         // 显示完成
    wire w_timeout;           // 倒计时结束
    wire w_tx_busy;           // 串口发送忙 (Display模块内部使用，可选反馈)

    // --- 存储总线信号 (Storage Bus) ---
    // MUX 输出端 (直接连到 Storage)
    wire [7:0] w_storage_addr;
    wire [31:0] w_storage_data;
    wire w_storage_we;
    wire [31:0] w_storage_out; // Storage 的读出数据 (广播给所有模块)

    // --- 子模块的请求信号 (Requests) ---
    // Input Subsystem
    wire [7:0] w_input_addr;
    wire [31:0] w_input_data;
    wire w_input_we;

    // Calculator Core
    wire [7:0] w_calc_addr;
    wire [31:0] w_calc_data;
    wire w_calc_we;
    wire [31:0] w_cycle_count; // 卷积周期计数

    // Display Subsystem
    wire [7:0] w_disp_addr;

    // --- UI 显示信号 ---
    wire [3:0] w_time_val;     // 倒计时秒数
    wire [31:0] w_seg_val_muxed; // 选中的要显示的数值
    wire [1:0] w_seg_mode;     // 显示模式 (数字/字符)

    // ============================================================
    // 2. 模块实例化 (Instance Connectivity)
    // ============================================================

    // --- 2.1 主控大脑 (FSM) ---
    FSM_Controller u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .sw(sw),
        .btn(btn),
        // Flags
        .w_rx_done(w_rx_done),
        .w_error_flag(w_error_flag),
        .w_gen_done(1'b0), // 暂时没写 Gen 模块，给 0
        .w_disp_done(w_disp_done),
        .w_calc_done(w_calc_done),
        .w_timeout(w_timeout),
        // Controls
        .w_state(w_state),
        .w_en_input(w_en_input),
        .w_start_calc(w_start_calc),
        .w_start_disp(w_start_disp),
        .w_start_timer(w_start_timer),
        .w_op_code(w_op_code),
        .led(led)
    );

    // --- 2.2 存储仲裁器 (Storage MUX) ---
    Storage_Access_MUX u_storage_mux (
        .w_state(w_state),
        // Channel A: Input
        .w_input_addr(w_input_addr),
        .w_input_data(w_input_data),
        .w_input_we(w_input_we),
        // Channel B: Calc
        .w_calc_addr(w_calc_addr),
        .w_calc_data(w_calc_data),
        .w_calc_we(w_calc_we),
        // Channel C: Display
        .w_disp_addr(w_disp_addr),
        // Outputs
        .w_storage_addr(w_storage_addr),
        .w_storage_data(w_storage_data),
        .w_storage_we(w_storage_we)
    );

    // --- 2.3 核心仓库 (Matrix Storage) ---
    Matrix_Storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we),
        .w_storage_addr(w_storage_addr),
        .w_storage_data(w_storage_data),
        .w_storage_out(w_storage_out) // 广播输出
    );

    // --- 2.4 输入子系统 (Input) ---
    Input_Subsystem u_input (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx),
        .w_en_input(w_en_input),
        // To MUX
        .w_input_we(w_input_we),
        .w_input_addr(w_input_addr),
        .w_input_data(w_input_data),
        // Flags
        .w_rx_done(w_rx_done),
        .w_error_flag(w_error_flag)
    );

    // --- 2.5 计算核心 (Calculator) ---
    Calculator_Core u_calc (
        .clk(clk),
        .rst_n(rst_n),
        .w_start_calc(w_start_calc),
        .w_op_code(w_op_code),
        .w_scalar_val({24'd0, sw}), // 标量值暂时直接取开关低8位(或按需求修改)
        .w_storage_out(w_storage_out),
        // To MUX
        .w_calc_we(w_calc_we),
        .w_calc_addr(w_calc_addr),
        .w_calc_data(w_calc_data),
        .w_calc_done(w_calc_done),
        .w_cycle_count(w_cycle_count)
    );

    // --- 2.6 显示子系统 (Display) ---
    Display_Subsystem u_disp (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx_pin(uart_tx),
        .w_start_disp(w_start_disp),
        .w_disp_done(w_disp_done),
        .w_tx_busy(w_tx_busy),
        // From Storage
        .w_disp_addr(w_disp_addr),
        .w_storage_out(w_storage_out)
    );

    // --- 2.7 倒计时器 (Timer) ---
    Timer_Unit u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .w_start_timer(w_start_timer),
        .sw(sw),
        .w_timeout(w_timeout),
        .w_time_val(w_time_val)
    );

    // --- 2.8 显示数据选择器 (Display MUX) ---
    Display_Data_MUX u_disp_mux (
        .w_state(w_state),
        .w_time_val(w_time_val),
        .w_cycle_count(w_cycle_count),
        .w_op_code(w_op_code),
        .w_seg_data(w_seg_val_muxed),
        .w_seg_mode(w_seg_mode)
    );

    // --- 2.9 数码管驱动 (Seg Driver) ---
    Seg7_Driver u_seg_driver (
        .clk(clk),
        .rst_n(rst_n),
        .w_seg_data(w_seg_val_muxed),
        .w_seg_mode(w_seg_mode),
        .seg_sel(seg_sel),
        .seg_data(seg_data)
    );

endmodule