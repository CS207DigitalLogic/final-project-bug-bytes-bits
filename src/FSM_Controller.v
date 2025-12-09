module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // =========================================================================
    // 1. 物理接口
    // =========================================================================
    input wire [7:0] sw,      // sw[1:0] 模式选择, sw[7:5] 运算类型选择
    input wire [4:0] btn,     // btn[0] 确认键
    output reg [7:0] led,     // 状态/报错指示

    // =========================================================================
    // 2. Input Subsystem 交互接口
    // =========================================================================
    input wire w_dims_valid,  // Input: 维度读取完成 (Mode 1) / 请求分配 (Mode 0)
    input wire [31:0] i_dim_m,// Input: 矩阵行数
    input wire [31:0] i_dim_n,// Input: 矩阵列数
    input wire w_rx_done,     // Input: 任务完成
    input wire w_error_flag,  // Input: 出错标志 (用于驱动 LED)
    
    // Input 接口 (ID模式)
    input wire [31:0] i_input_id_val, // Input: 读取到的ID (1或2)
    input wire w_id_valid,            // Input: ID读取完成
    
    output reg w_en_input,    // 启用 Input 模块
    output reg w_is_gen_mode, // 0=手动, 1=生成
    output reg [1:0] w_task_mode, // 0=存, 1=读维度, 2=读ID
    output reg w_addr_ready,  // FSM: 地址分配好了
    output reg [7:0] w_base_addr_to_input, // 分配好的基地址

    // =========================================================================
    // 3. Display Subsystem 交互接口
    // =========================================================================
    input wire w_disp_done,           // Display: 展示完成
    input wire [1:0] i_disp_lut_idx_req, // Display: 请求查阅账本的第几行 (Summary模式用)
    
    output reg w_en_display,          // FSM: 启动展示
    output reg [1:0] w_disp_mode,     // 0=单矩阵(结果), 1=列表(选数), 2=汇总, 3=缓存回显
    output reg [7:0] w_disp_base_addr,// 告诉 Display 的基地址
    output reg [1:0] w_disp_total_cnt,// 告诉 Display 这种矩阵有几个
    output reg [31:0] w_disp_m,       // 维度 M
    output reg [31:0] w_disp_n,       // 维度 N
    output reg [1:0] w_disp_selected_id, // 告诉 Display 回显第几个缓存 (1或2)
    
    // 输出给 Display 的统计信息 (确保 Mode 2 正常工作)
    output wire [7:0] w_system_total_count, 
    output wire [2:0] w_system_types_count,

    // (单矩阵模式备用目标地址，如果 Display 逻辑依赖它)
    output reg [7:0] w_disp_target_addr, 

    // =========================================================================
    // 4. Calculator Core 交互接口
    // =========================================================================
    input wire w_calc_done,       // Calc: 计算完成
    output reg w_start_calc,      // FSM: 启动计算
    output reg [2:0] w_op_code,   // 运算类型
    output reg [7:0] w_op1_addr,  // 操作数1地址
    output reg [7:0] w_op2_addr,  // 操作数2地址
    
    // 补充缺失的维度信号，否则计算器无法工作
    output reg [31:0] w_op1_m,
    output reg [31:0] w_op1_n,
    output reg [31:0] w_op2_m,
    output reg [31:0] w_op2_n,
    
    output reg [7:0] w_res_addr,  // 结果存放地址 (需要FSM分配)
    
    // 调试端口
    output wire [3:0] w_state
);

    // =========================================================================
    // 参数定义
    // =========================================================================
    localparam S_IDLE           = 4'd0;
    localparam S_INPUT_MODE     = 4'd1; 
    localparam S_GEN_MODE       = 4'd2; 
    
    // 计算流程状态
    localparam S_CALC_SELECT_OP    = 4'd3; 
    localparam S_CALC_GET_DIM      = 4'd4; 
    localparam S_CALC_SHOW_SUMMARY = 4'd5;
    localparam S_CALC_FILTER       = 4'd6; // 查表筛选
    localparam S_CALC_SHOW_LIST    = 4'd7; // 显示列表
    localparam S_CALC_GET_ID       = 4'd8; // 读ID (1或2)
    localparam S_CALC_SHOW_MAT     = 4'd9; // 回显确认
    localparam S_CALC_EXECUTE      = 4'd10; // 执行计算 & 登记
    localparam S_CALC_RES_SHOW     = 4'd11;// 结果展示
    
    // 主菜单-展示模式专用状态
    localparam S_MENU_DISP_GET_DIM = 4'd12;
    localparam S_MENU_DISP_FILTER  = 4'd13;
    localparam S_MENU_DISP_SHOW    = 4'd14;
    
    localparam S_ERROR             = 4'd15;

    localparam MAX_TYPES = 4;

    // =========================================================================
    // 内部寄存器
    // =========================================================================
    reg [3:0] current_state, next_state; 

    // --- MMU 账本 ---
    reg [31:0] lut_m [0:MAX_TYPES-1];     
    reg [31:0] lut_n [0:MAX_TYPES-1];
    reg [7:0]  lut_start_addr [0:MAX_TYPES-1];
    reg        lut_idx [0:MAX_TYPES-1]; 
    reg [1:0]  lut_valid_cnt [0:MAX_TYPES-1]; 
    reg [2:0]  lut_count;
    reg [7:0]  free_ptr;

    // --- 计算上下文寄存器 ---
    reg [2:0] r_op_code;    
    reg       r_stage;      
    reg       r_target_stage; 
    
    // 筛选/选中结果
    reg [1:0] r_hit_type_idx; // 命中了账本的哪一行 (0~3)
    reg       r_hit_found;    // 是否找到匹配项
    reg [1:0] r_selected_id;  // 用户选中的 ID (1或2)
    
    // 操作数信息 (完整记录 Op1 和 Op2)
    reg [7:0]  r_op1_addr, r_op2_addr; 
    reg [31:0] r_op1_m, r_op1_n; 
    reg [31:0] r_op2_m, r_op2_n; 
    
    // 结果信息 (预判)
    reg [31:0] r_res_m, r_res_n;

    // 按键消抖 
    reg btn_d0, btn_d1;
    wire btn_confirm_pose;
    assign btn_confirm_pose = btn_d0 & ~btn_d1;

    // =========================================================================
    // 0. 辅助组合逻辑 (MMU查表 & Display Mux & 统计)
    // =========================================================================
    
    // --- MMU 查表逻辑 ---
    reg       calc_match_found;
    reg [2:0] calc_match_index;
    reg [7:0] calc_final_addr;
    reg [7:0] single_mat_size;
    integer i;

    always @(*) begin
        calc_match_found = 0;
        calc_match_index = 0;
        calc_final_addr  = 0;
        single_mat_size  = (i_dim_m * i_dim_n); // 纯数据大小 (无头信息)

        if (w_dims_valid) begin
            for (i = 0; i < MAX_TYPES; i = i + 1) begin
                if (i < lut_count) begin
                    if (lut_m[i] == i_dim_m && lut_n[i] == i_dim_n) begin
                        calc_match_found = 1;
                        calc_match_index = i[2:0];
                    end
                end
            end

            if (calc_match_found) begin
                if (lut_idx[calc_match_index] == 0)
                    calc_final_addr = lut_start_addr[calc_match_index];
                else
                    calc_final_addr = lut_start_addr[calc_match_index] + single_mat_size;
            end 
            else begin
                calc_final_addr = free_ptr;
            end
        end
    end

    // --- Display 参数 MUX ---
    always @(*) begin
        // 默认值
        w_disp_m = 0; w_disp_n = 0; w_disp_total_cnt = 0; w_disp_base_addr = 0;

        if (w_disp_mode == 2) begin 
            // --- 场景: 汇总模式  ---
            w_disp_m         = lut_m[i_disp_lut_idx_req];
            w_disp_n         = lut_n[i_disp_lut_idx_req];
            w_disp_total_cnt = lut_valid_cnt[i_disp_lut_idx_req];
            w_disp_base_addr = 0; 
        end 
        else if (current_state == S_CALC_RES_SHOW) begin
            // --- 场景: 计算结果展示 ---
            w_disp_m         = r_res_m;
            w_disp_n         = r_res_n;
            w_disp_total_cnt = 1; 
            w_disp_base_addr = w_res_addr; 
        end
        else if (current_state == S_MENU_DISP_SHOW) begin
            // --- 场景: 主菜单回显展示 ---
            w_disp_m         = i_dim_m; 
            w_disp_n         = i_dim_n;
            w_disp_total_cnt = 1;
            w_disp_base_addr = free_ptr; // 刚才存的地方
        end
        else begin 
            // --- 场景: 列表/选数模式 ---
            w_disp_m         = lut_m[r_hit_type_idx];
            w_disp_n         = lut_n[r_hit_type_idx];
            w_disp_total_cnt = lut_valid_cnt[r_hit_type_idx];
            w_disp_base_addr = lut_start_addr[r_hit_type_idx];
        end
    end

    // --- 统计输出逻辑 ---
    assign w_system_total_count = lut_valid_cnt[0] + lut_valid_cnt[1] + lut_valid_cnt[2] + lut_valid_cnt[3];
    assign w_system_types_count = lut_count;
    assign w_state = current_state;

    // =========================================================================
    // Stage 1: 状态寄存器更新 (Sequential Logic)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            current_state <= S_IDLE;
        else 
            current_state <= next_state;
    end

    // =========================================================================
    // Stage 2: 次态逻辑判断 (Combinational Logic)
    // =========================================================================
    always @(*) begin
        next_state = current_state; // 默认保持

        case (current_state)
            S_IDLE: begin
                if (btn_confirm_pose) begin
                    case (sw[1:0])
                        2'b00: next_state = S_INPUT_MODE;
                        2'b01: next_state = S_GEN_MODE;
                        2'b10: next_state = S_CALC_SELECT_OP;
                        2'b11: next_state = S_MENU_DISP_GET_DIM;
                    endcase
                end
            end

            S_INPUT_MODE, S_GEN_MODE: begin
                if (w_rx_done) next_state = S_IDLE;
            end

            S_MENU_DISP_GET_DIM: begin
                if (w_rx_done) next_state = S_MENU_DISP_SHOW;
            end

            S_MENU_DISP_SHOW: begin
                if (w_disp_done) next_state = S_IDLE;
            end

            S_CALC_SELECT_OP: begin
                if (btn_confirm_pose) next_state = S_CALC_SHOW_SUMMARY;
            end

            S_CALC_SHOW_SUMMARY: begin
                if (w_disp_done) next_state = S_CALC_GET_DIM;
            end

            S_CALC_GET_DIM: begin
                if (w_dims_valid) next_state = S_CALC_FILTER;
            end

            S_CALC_FILTER: begin
                next_state = S_CALC_SHOW_LIST;
            end

            S_CALC_SHOW_LIST: begin
                if (r_hit_found == 0) next_state = S_ERROR;
                else if (w_disp_done) next_state = S_CALC_GET_ID;
            end

            S_CALC_GET_ID: begin
                if (w_id_valid) begin
                    if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx])
                        next_state = S_CALC_SHOW_MAT;
                    else
                        next_state = S_ERROR;
                end
            end

            S_CALC_SHOW_MAT: begin
                if (w_disp_done) begin
                    if (r_stage < r_target_stage) next_state = S_CALC_GET_DIM;
                    else next_state = S_CALC_EXECUTE;
                end
            end

            S_CALC_EXECUTE: begin
                if (w_calc_done) next_state = S_CALC_RES_SHOW;
            end

            S_CALC_RES_SHOW: begin
                if (w_disp_done) next_state = S_IDLE;
            end

            S_ERROR: begin
                if (btn_confirm_pose) next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // Stage 3: 数据输出与寄存器更新 (Sequential Logic)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 数据复位
            lut_count <= 0; free_ptr <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            
            // 输出复位
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0;
            w_addr_ready <= 0;
            r_res_m <= 0; r_res_n <= 0;
            led <= 0;
            
            // 计算器参数复位 [新增]
            w_op1_addr <= 0; w_op2_addr <= 0; w_res_addr <= 0;
            w_op1_m <= 0; w_op1_n <= 0;
            w_op2_m <= 0; w_op2_n <= 0;
            
            // 中间变量复位
            btn_d0 <= 0; btn_d1 <= 0;
        end 
        else begin
            // 默认值 (脉冲信号自动拉低)
            w_addr_ready <= 0; 
            w_start_calc <= 0;

            // 按键消抖
            btn_d0 <= btn[0];
            btn_d1 <= btn_d0;

            case (current_state)
                S_IDLE: begin
                    w_en_input <= 0; 
                    w_en_display <= 0;
                    led <= 8'b0000_0001; // 待机灯
                end

                S_INPUT_MODE, S_GEN_MODE: begin
                    w_en_input <= 1;
                    w_task_mode <= 0;
                    w_is_gen_mode <= (current_state == S_GEN_MODE);
                    
                    // LED 错误映射逻辑
                    if (w_error_flag) 
                        led <= 8'b1000_0001; // 报错红灯
                    else 
                        led <= 8'b0000_0001; // 正常
                    
                    // MMU 动态分配逻辑
                    if (w_dims_valid && !w_addr_ready) begin
                        w_base_addr_to_input <= calc_final_addr;
                        w_addr_ready <= 1; // 握手脉冲

                        if (calc_match_found) begin
                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                            if (lut_valid_cnt[calc_match_index] < 2)
                                lut_valid_cnt[calc_match_index] <= lut_valid_cnt[calc_match_index] + 1;
                        end 
                        else begin
                            if (lut_count < MAX_TYPES) begin
                                lut_m[lut_count] <= i_dim_m;
                                lut_n[lut_count] <= i_dim_n;
                                lut_start_addr[lut_count] <= free_ptr;
                                lut_idx[lut_count] <= 1;
                                lut_valid_cnt[lut_count] <= 1;
                                
                                free_ptr <= free_ptr + (single_mat_size << 1); 
                                lut_count <= lut_count + 1;
                            end
                        end
                    end
                    
                    if (w_rx_done) begin
                        w_en_input <= 0;
                    end
                end

                S_MENU_DISP_GET_DIM: begin
                    w_en_input <= 1;
                    w_task_mode <= 0;
                    w_base_addr_to_input <= free_ptr;
                    
                    if (w_dims_valid && !w_addr_ready) begin
                        w_addr_ready <= 1;
                    end
                    if (w_rx_done) begin
                        w_en_input <= 0;
                    end
                end

                S_MENU_DISP_SHOW: begin
                    w_en_display <= 1;
                    w_disp_mode <= 0;
                    if (w_disp_done) w_en_display <= 0;
                end

                S_CALC_SELECT_OP: begin
                    r_op_code <= sw[7:5]; 
                    if (sw[7:5] == 3'b000) r_target_stage <= 0;
                    else r_target_stage <= 1; 
                    r_stage <= 0; 
                end

                S_CALC_SHOW_SUMMARY: begin
                    w_en_display <= 1;
                    w_disp_mode  <= 2;
                    if (w_disp_done) w_en_display <= 0;
                end

                S_CALC_GET_DIM: begin
                    w_en_input <= 1;
                    w_task_mode <= 1; 
                    if (w_dims_valid) w_en_input <= 0;
                end

                S_CALC_FILTER: begin
                    r_hit_found <= 0;
                    r_hit_type_idx <= 0;
                    for (i=0; i<MAX_TYPES; i=i+1) begin
                        if (i < lut_count && lut_m[i] == i_dim_m && lut_n[i] == i_dim_n && lut_valid_cnt[i] > 0) begin
                            r_hit_found <= 1;
                            r_hit_type_idx <= i[1:0]; 
                        end
                    end
                end

                S_CALC_SHOW_LIST: begin
                    if (r_hit_found != 0) begin
                        w_en_display <= 1;
                        w_disp_mode <= 1;
                        if (w_disp_done) w_en_display <= 0;
                    end
                end

                S_CALC_GET_ID: begin
                    w_en_input <= 1;
                    w_task_mode <= 2;
                    
                    if (w_id_valid) begin
                        if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx]) begin
                            r_selected_id <= i_input_id_val[1:0];
                            
                            // 在选中操作数时，将维度和地址同时锁存到输出端口
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op1_m <= lut_m[r_hit_type_idx];
                                w_op1_n <= lut_n[r_hit_type_idx];
                                
                                // 内部更新
                                r_op1_m <= i_dim_m;
                                r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op2_m <= lut_m[r_hit_type_idx];
                                w_op2_n <= lut_n[r_hit_type_idx];
                                
                                // 内部更新
                                r_op2_m <= i_dim_m;
                                r_op2_n <= i_dim_n;
                            end
                            w_en_input <= 0;
                        end
                    end
                end

                S_CALC_SHOW_MAT: begin
                    w_en_display <= 1;
                    w_disp_mode <= 3; 
                    w_disp_selected_id <= r_selected_id;
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        if (r_stage < r_target_stage) r_stage <= r_stage + 1;
                    end
                end

                S_CALC_EXECUTE: begin
                    w_start_calc <= 1; 
                    w_op_code <= r_op_code;
                    w_res_addr <= free_ptr; 
                    
                    // 预判结果维度
                    if (r_op_code == 3'b000) begin // 转置
                        r_res_m <= r_op1_n; r_res_n <= r_op1_m;
                    end
                    else if (r_op_code == 3'b010) begin // 乘法
                        r_res_m <= r_op1_m; r_res_n <= r_op2_n;
                    end
                    else begin // 加法
                        r_res_m <= r_op1_m; r_res_n <= r_op1_n;
                    end
                    
                    if (w_calc_done) begin
                        w_start_calc <= 0;
                        // 登记新矩阵
                        if (lut_count < MAX_TYPES) begin
                            lut_m[lut_count] <= r_res_m;
                            lut_n[lut_count] <= r_res_n;
                            lut_start_addr[lut_count] <= free_ptr; 
                            lut_valid_cnt[lut_count] <= 1;
                            lut_idx[lut_count] <= 1;
                            free_ptr <= free_ptr + (r_res_m * r_res_n);
                            lut_count <= lut_count + 1;
                        end
                    end
                end
                
                S_CALC_RES_SHOW: begin
                    w_en_display <= 1;
                    w_disp_mode <= 0; 
                    if (w_disp_done) w_en_display <= 0;
                end

                S_ERROR: begin
                    led <= 8'b1111_1111;
                end
            endcase
        end
    end

endmodule