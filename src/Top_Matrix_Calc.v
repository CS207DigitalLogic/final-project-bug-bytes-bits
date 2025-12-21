module Top_Module (
    input wire clk1,

    // --- 物理接口 ---
    input wire uart_rx,      
    output wire uart_tx,     
    
    input wire [7:0] sw,    
    input wire [7:0] ssw, 
    input wire [4:0] btn,    
    output wire [7:0] led,   
    
    output wire [7:0] seg,   
    output wire [3:0] an     
);

    // =========================================================================
    // 1. 内部连线定义
    // =========================================================================
    
    // --- FSM 信号 ---
    wire w_en_input, w_en_display, w_start_calc;
    wire w_is_gen_mode;
    wire [1:0] w_task_mode;
    wire w_addr_ready;
    wire [8:0] w_base_addr_to_input;
    wire [2:0] w_disp_mode;
    wire [8:0] w_disp_base_addr;
    wire [1:0] w_disp_total_cnt;
    wire [31:0] w_disp_m, w_disp_n;
    wire [1:0] w_disp_selected_id;
    wire [8:0] w_disp_target_addr;
    wire [2:0] w_op_code;
    wire [8:0] w_op1_addr, w_op2_addr, w_res_addr;
    wire [31:0] w_op1_m, w_op1_n, w_op2_m, w_op2_n;
    
    wire [4:0] w_state; 

    // --- Input Subsystem 信号 ---
    wire w_input_rx_done;
    wire w_input_error;
    wire w_dims_valid;
    wire [31:0] w_dim_m, w_dim_n;
    wire w_id_valid;
    wire [31:0] w_input_id_val;
    
    // --- Display Subsystem 信号 ---
    wire w_disp_done;
    wire [4:0] w_disp_lut_idx_req;
    wire [7:0] w_sys_total_cnt;    
    wire [4:0] w_sys_types_count;  

    // --- Calculator Core 信号 ---
    wire w_calc_done;
    wire [8:0] w_calc_req_addr;
    wire [8:0] w_calc_waddr;
    wire [31:0] w_calc_wdata;
    wire w_calc_we;
    wire [8:0] w_calc_addr_merged;
    assign w_calc_addr_merged = (w_calc_we) ? w_calc_waddr : w_calc_req_addr;

    // --- Storage MUX & Memory 信号 ---
    wire [8:0] w_input_addr;
    wire [31:0] w_input_data;
    wire w_input_we;
    wire [8:0] w_disp_req_addr;
    wire [8:0] w_storage_addr;
    wire [31:0] w_storage_wdata;
    wire w_storage_we;
    wire [31:0] w_storage_rdata;

    // --- Timer & Seg7 信号 ---
    wire w_timeout;
    wire [3:0] w_timer_val;
    wire w_timer_start_pulse;
    (* mark_debug = "true" *)wire w_seg_en;
    (* mark_debug = "true" *)wire w_seg_mode;
    
    wire w_logic_error; 

    wire rst_n;
    assign rst_n = ~btn[4];

    wire clk;

    clk_div u_clk(.clk(clk1), .rst_n(rst_n), .clk_out(clk));

    // =========================================================================
    // 2. 辅助逻辑: 定时器控制与显示模式
    // =========================================================================
    
    localparam S_CALC_START = 5'd3;  
    localparam S_CALC_END   = 5'd17; 
    localparam S_ERROR      = 5'd21; 

    reg [4:0] state_d;
    reg w_input_error_d;
    reg w_logic_error_d;

    always @(posedge clk) begin
        state_d <= w_state;
        w_input_error_d <= w_input_error;
        w_logic_error_d <= w_logic_error;
    end

    // A. Timer 启动脉冲
    // 【修改】移除了 S_ERROR 的触发条件
    // 只在检测到具体的错误发生瞬间（输入错误或逻辑错误）才启动倒计时
    assign w_timer_start_pulse = (w_logic_error && !w_logic_error_d);

    // B. 数码管使能逻辑
    // 【修改】
    // 1. 移除了 S_ERROR 作为开启条件
    // 2. 增加了 && (w_state != S_ERROR) 作为强制关闭条件
    //    这意味着一旦进入 ERROR 状态，哪怕 w_input_error 还是 1，数码管也会强制熄灭
    assign w_seg_en = ((w_state >= S_CALC_START && w_state <= S_CALC_END) ||
                       (w_logic_error)) && (w_state != S_ERROR);
    
    // C. 显示模式
    // 【修改】移除了 S_ERROR 的判断
    assign w_seg_mode = ((w_input_error) || 
                         (w_logic_error)) ? 1'b1 : 1'b0;

    // =========================================================================
    // 3. 模块例化
    // =========================================================================

    FSM_Controller u_fsm (
        .clk(clk), .rst_n(rst_n),
        .sw(sw), .btn(btn), .led(led),
        
        .w_dims_valid(w_dims_valid), .i_dim_m(w_dim_m), .i_dim_n(w_dim_n),
        .w_rx_done(w_input_rx_done), .w_error_flag(w_input_error), 
        .w_timeout(w_timeout), 
        
        .i_input_id_val(w_input_id_val), .w_id_valid(w_id_valid),
        .w_en_input(w_en_input), .w_is_gen_mode(w_is_gen_mode),
        .w_task_mode(w_task_mode), .w_addr_ready(w_addr_ready),
        .w_base_addr_to_input(w_base_addr_to_input),
        
        .w_disp_done(w_disp_done), .i_disp_lut_idx_req(w_disp_lut_idx_req),
        .w_en_display(w_en_display), .w_disp_mode(w_disp_mode),
        .w_disp_base_addr(w_disp_base_addr), .w_disp_total_cnt(w_disp_total_cnt),
        .w_disp_m(w_disp_m), .w_disp_n(w_disp_n),
        .w_disp_selected_id(w_disp_selected_id),
        .w_system_total_count(w_sys_total_cnt), .w_system_types_count(w_sys_types_count),
        .w_disp_target_addr(w_disp_target_addr),
        
        .w_calc_done(w_calc_done), .w_start_calc(w_start_calc),
        .w_op_code(w_op_code),
        .w_op1_addr(w_op1_addr), .w_op2_addr(w_op2_addr), .w_res_addr(w_res_addr),
        .w_op1_m(w_op1_m), .w_op1_n(w_op1_n), 
        .w_op2_m(w_op2_m), .w_op2_n(w_op2_n),
        
        .w_state(w_state),
        .w_logic_error(w_logic_error) 
    );

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

    Calculator_Core u_calc (
        .clk(clk), .rst_n(rst_n),
        .i_start_calc(w_start_calc), .i_op_code(w_op_code), .o_calc_done(w_calc_done),
        .i_op1_addr(w_op1_addr), .i_op1_m(w_op1_m), .i_op1_n(w_op1_n),
        .i_op2_addr(w_op2_addr), .i_op2_m(w_op2_m), .i_op2_n(w_op2_n),
        .i_res_addr(w_res_addr),
        .o_calc_req_addr(w_calc_req_addr), 
        .i_storage_rdata(w_storage_rdata),
        .o_calc_we(w_calc_we), .o_calc_waddr(w_calc_waddr), .o_calc_wdata(w_calc_wdata)
    );

    Storage_Mux u_mux (
        .i_en_input(w_en_input), .i_en_display(w_en_display), .i_en_calc(w_start_calc),
        .i_input_addr(w_input_addr), .i_input_data(w_input_data), .i_input_we(w_input_we),
        .i_disp_addr(w_disp_req_addr),
        .i_calc_addr(w_calc_addr_merged), 
        .i_calc_data(w_calc_wdata), 
        .i_calc_we(w_calc_we),
        .o_storage_addr(w_storage_addr), .o_storage_data(w_storage_wdata), .o_storage_we(w_storage_we)
    );

    Matrix_storage u_storage (
        .clk(clk),
        .w_storage_we(w_storage_we),
        .w_storage_data(w_storage_wdata),
        .w_storage_addr(w_storage_addr),
        .w_storage_out(w_storage_rdata)
    );

    Timer_Unit #(
        .CLK_FREQ(25_000_000)
    ) u_timer (
        .clk(clk), .rst_n(rst_n),
        .i_start_timer(w_timer_start_pulse), 
        
        // Timer 运行条件：有错误发生 且 还没死机
        .i_en( (w_logic_error) && (w_state != S_ERROR) ), 
        
        .sw(ssw[3:0]), 
        .w_timeout(w_timeout),
        .w_time_val(w_timer_val)
    );

    Seg7_Driver u_seg (
        .clk(clk), .rst_n(rst_n),
        .i_en(w_seg_en),           
        .i_disp_mode(w_seg_mode),  
        .i_op_code(w_op_code),     
        .i_digit_val(w_timer_val), 
        .seg_data(seg),       
        .seg_sel(an)               
    );

endmodule