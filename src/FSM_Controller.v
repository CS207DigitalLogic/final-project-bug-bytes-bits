module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // --- 物理接口 ---
    input wire [7:0] sw,
    input wire [4:0] btn,
    output reg [7:0] led,

    // --- Input Subsystem ---
    input wire w_dims_valid,  
    input wire [31:0] i_dim_m,
    input wire [31:0] i_dim_n,
    input wire w_rx_done,     
    input wire w_error_flag,  
    input wire w_timeout,     // 【关键】接收超时信号
    
    input wire [31:0] i_input_id_val, 
    input wire w_id_valid,            
    
    output reg w_en_input,    
    output reg w_is_gen_mode, 
    output reg [1:0] w_task_mode, 
    output reg w_addr_ready,  
    output reg [7:0] w_base_addr_to_input, 

    // --- Display Subsystem ---
    input wire w_disp_done,           
    input wire [3:0] i_disp_lut_idx_req, 
    
    output reg w_en_display,          
    output reg [1:0] w_disp_mode,     
    output reg [7:0] w_disp_base_addr,
    output reg [1:0] w_disp_total_cnt,
    output reg [31:0] w_disp_m,       
    output reg [31:0] w_disp_n,       
    output reg [1:0] w_disp_selected_id, 
    
    output wire [7:0] w_system_total_count, 
    output wire [2:0] w_system_types_count,
    output reg [7:0] w_disp_target_addr, 

    // --- Calculator Core ---
    input wire w_calc_done,       
    output reg w_start_calc,      
    output reg [2:0] w_op_code,  
    output reg [7:0] w_op1_addr,  
    output reg [7:0] w_op2_addr,  
    output reg [31:0] w_op1_m,
    output reg [31:0] w_op1_n,
    output reg [31:0] w_op2_m,
    output reg [31:0] w_op2_n,
    output reg [7:0] w_res_addr,  
    
    output wire [4:0] w_state,
    output reg w_logic_error // 【新增】逻辑错误标志（给Top层控制倒计时）
);

    // =========================================================================
    // 参数与内部信号
    // =========================================================================
    localparam S_IDLE              = 5'd0;
    localparam S_INPUT_MODE        = 5'd1;
    localparam S_GEN_MODE          = 5'd2;
    localparam S_CALC_SELECT_OP    = 5'd3;
    localparam S_CALC_GET_DIM      = 5'd4; 
    localparam S_CALC_SHOW_SUMMARY = 5'd5;
    localparam S_CALC_FILTER       = 5'd6;
    localparam S_CALC_SHOW_LIST    = 5'd7;
    localparam S_CALC_GET_ID       = 5'd8;
    localparam S_CALC_SHOW_MAT     = 5'd9;
    localparam S_CALC_EXECUTE      = 5'd10;
    localparam S_CALC_RES_SHOW     = 5'd11;
    localparam S_MENU_DISP_GET_DIM = 5'd12;
    localparam S_MENU_DISP_FILTER  = 5'd13;
    localparam S_MENU_DISP_SHOW    = 5'd14;
    localparam S_ERROR             = 5'd15;
    localparam S_WAIT_DECISION     = 5'd16;

    localparam MAX_TYPES = 4;

    reg [4:0] current_state, next_state;
    
    // MMU 账本
    reg [31:0] lut_m [0:MAX_TYPES-1];
    reg [31:0] lut_n [0:MAX_TYPES-1];
    reg [7:0]  lut_start_addr [0:MAX_TYPES-1];
    reg        lut_idx [0:MAX_TYPES-1];
    reg [1:0]  lut_valid_cnt [0:MAX_TYPES-1];
    reg [2:0]  lut_count;
    reg [7:0]  free_ptr;

    // 上下文
    reg [2:0] r_op_code;
    reg       r_stage;
    reg       r_target_stage;
    reg [1:0] r_hit_type_idx; 
    reg       r_hit_found;
    reg [1:0] r_selected_id;  
    
    reg [7:0]  r_op1_addr, r_op2_addr;
    reg [31:0] r_op1_m, r_op1_n; 
    reg [31:0] r_op2_m, r_op2_n; 
    reg [31:0] r_res_m, r_res_n;
    reg [4:0] r_retry_state;

    reg btn0_d0, btn0_d1;
    reg btn1_d0, btn1_d1;
    wire btn_confirm_pose;
    wire btn_retry_pose;
    
    assign btn_confirm_pose = btn0_d0 & ~btn0_d1;
    assign btn_retry_pose   = btn1_d0 & ~btn1_d1;

    // =========================================================================
    // 0. 辅助组合逻辑 
    // =========================================================================
    reg       calc_match_found;
    reg [2:0] calc_match_index;
    reg [7:0] calc_final_addr;
    reg [7:0] single_mat_size;
    integer i;
    reg [31:0] calc_pred_m, calc_pred_n;
    reg [31:0] search_m, search_n;
    reg        enable_search;

    // (预测逻辑保持不变)
    always @(*) begin
        calc_pred_m = 0; calc_pred_n = 0;
        if (r_op_code == 3'b000) begin      // Transpose
            calc_pred_m = r_op1_n; calc_pred_n = r_op1_m;
        end else if (r_op_code == 3'b010) begin // Scalar Mul
            calc_pred_m = r_op1_m; calc_pred_n = r_op2_n; 
        end else begin                      // Add / MatMul
            calc_pred_m = r_op1_m; calc_pred_n = r_op1_n;
        end
    end

    // (查表逻辑保持不变)
    always @(*) begin
        calc_match_found = 0;
        calc_match_index = 0;
        calc_final_addr  = 0;
        
        if (current_state == S_INPUT_MODE || current_state == S_GEN_MODE || current_state == S_MENU_DISP_GET_DIM) begin
            search_m = i_dim_m; search_n = i_dim_n;
            enable_search = w_dims_valid; 
        end else begin
            search_m = calc_pred_m; search_n = calc_pred_n;
            enable_search = (current_state == S_CALC_EXECUTE); 
        end

        single_mat_size  = (search_m * search_n);
        if (enable_search) begin
            for (i = 0; i < MAX_TYPES; i = i + 1) begin
                if (i < lut_count) begin
                    if (lut_m[i] == search_m && lut_n[i] == search_n) begin
                        calc_match_found = 1;
                        calc_match_index = i[2:0];
                    end
                end
            end
            if (calc_match_found) begin
                if (lut_idx[calc_match_index] == 0) calc_final_addr = lut_start_addr[calc_match_index];
                else calc_final_addr = lut_start_addr[calc_match_index] + single_mat_size;
            end 
            else begin
                calc_final_addr = free_ptr;
            end
        end
    end

    // (Display MUX 保持不变)
    always @(*) begin
        w_disp_m = 0; w_disp_n = 0; w_disp_total_cnt = 0; w_disp_base_addr = 0;
        if (w_disp_mode == 2) begin 
            w_disp_m = lut_m[i_disp_lut_idx_req]; w_disp_n = lut_n[i_disp_lut_idx_req];
            w_disp_total_cnt = lut_valid_cnt[i_disp_lut_idx_req];
            w_disp_base_addr = 0;
        end 
        else if (current_state == S_CALC_RES_SHOW) begin
            w_disp_m = r_res_m; w_disp_n = r_res_n;
            w_disp_total_cnt = 1; w_disp_base_addr = w_res_addr;
        end
        else if (current_state == S_MENU_DISP_SHOW) begin
            w_disp_m = i_dim_m; w_disp_n = i_dim_n;
            w_disp_total_cnt = 1; w_disp_base_addr = free_ptr;
        end
        else begin 
            w_disp_m = lut_m[r_hit_type_idx]; w_disp_n = lut_n[r_hit_type_idx];
            w_disp_total_cnt = lut_valid_cnt[r_hit_type_idx];
            w_disp_base_addr = lut_start_addr[r_hit_type_idx];
        end
    end

    assign w_system_total_count = lut_valid_cnt[0] + lut_valid_cnt[1] + lut_valid_cnt[2] + lut_valid_cnt[3];
    assign w_system_types_count = lut_count;
    assign w_state = current_state;

    // =========================================================================
    // Stage 1: 状态跳转
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    // =========================================================================
    // Stage 2: 次态逻辑 (重点修改：错误重试逻辑)
    // =========================================================================
    always @(*) begin
        next_state = current_state;
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
                if (w_rx_done) next_state = S_WAIT_DECISION;
                else if (w_timeout) next_state = S_ERROR;
            end

            S_MENU_DISP_GET_DIM: begin
                if (w_rx_done) next_state = S_MENU_DISP_SHOW;
                else if (w_timeout) next_state = S_ERROR; // 增加超时检查
            end

            S_MENU_DISP_SHOW: begin
                if (w_disp_done) next_state = S_WAIT_DECISION;
            end

            S_CALC_SELECT_OP: begin
                if (btn_confirm_pose) next_state = S_CALC_SHOW_SUMMARY;
            end

            S_CALC_SHOW_SUMMARY: begin
                if (w_disp_done) next_state = S_CALC_GET_DIM;
            end

            S_CALC_GET_DIM: begin
                // 【修改】在此处检查超时，如果用户一直不输或输错多次导致超时
                if (w_timeout) next_state = S_ERROR;
                else if (w_dims_valid) next_state = S_CALC_FILTER;
            end

            S_CALC_FILTER: begin
                // 自动跳到 List，如果找不到，在 List 状态里判决
                next_state = S_CALC_SHOW_LIST;
            end

            S_CALC_SHOW_LIST: begin
                // 【修改】如果查不到矩阵 (Logic Error)：
                // 不要跳 S_ERROR，而是跳回 S_CALC_GET_DIM 允许重输
                if (r_hit_found == 0) next_state = S_CALC_GET_DIM;
                else if (w_disp_done) next_state = S_CALC_GET_ID;
            end

            S_CALC_GET_ID: begin
                // 【修改】在此处检查超时
                if (w_timeout) next_state = S_ERROR;
                else if (w_id_valid) begin
                    // 如果 ID 合法，继续
                    if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx])
                        next_state = S_CALC_SHOW_MAT;
                    // 如果 ID 不合法，【保持当前状态】，由 Stage 3 输出逻辑错误信号触发倒计时
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
                if (w_disp_done) next_state = S_WAIT_DECISION;
            end

            S_WAIT_DECISION: begin
                if (btn_confirm_pose) next_state = S_IDLE;
                else if (btn_retry_pose) next_state = r_retry_state;
            end

            S_ERROR: begin
                if (btn_confirm_pose) next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // Stage 3: 数据输出与寄存器更新
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ... (复位逻辑同原代码) ...
            lut_count <= 0; free_ptr <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0; w_addr_ready <= 0;
            r_res_m <= 0; r_res_n <= 0; led <= 0;
            w_op1_addr <= 0; w_op2_addr <= 0; w_res_addr <= 0;
            w_op1_m <= 0; w_op1_n <= 0; w_op2_m <= 0; w_op2_n <= 0;
            btn0_d0 <= 0; btn0_d1 <= 0; btn1_d0 <= 0; btn1_d1 <= 0;
            r_retry_state <= S_IDLE;
            w_logic_error <= 0; // 【新增】复位
        end 
        else begin
            w_addr_ready <= 0; w_start_calc <= 0;

            btn0_d0 <= btn[0]; btn0_d1 <= btn0_d0;
            btn1_d0 <= btn[1]; btn1_d1 <= btn1_d0;

            case (current_state)
                S_IDLE: begin
                    w_en_input <= 0; w_en_display <= 0; w_logic_error <= 0;
                    led <= 8'b0000_0001; 
                    if (btn_confirm_pose) begin
                        case (sw[1:0])
                            2'b00: r_retry_state <= S_INPUT_MODE;
                            2'b01: r_retry_state <= S_GEN_MODE;
                            2'b10: r_retry_state <= S_CALC_SELECT_OP;
                            2'b11: r_retry_state <= S_MENU_DISP_GET_DIM;
                        endcase
                    end
                end

                S_INPUT_MODE, S_GEN_MODE: begin
                    w_en_input <= 1; w_task_mode <= 0;
                    w_is_gen_mode <= (current_state == S_GEN_MODE);
                    
                    // LED 错误指示
                    if (w_error_flag) led <= 8'b1111_1111;
                    else if (w_is_gen_mode) led <= 8'b0000_0100;
                    else led <= 8'b0000_0010;
                    
                    // 地址握手与 LUT 更新逻辑保持不变 ...
                    if (w_dims_valid) begin
                        w_addr_ready <= 1; w_base_addr_to_input <= calc_final_addr;
                    end else w_addr_ready <= 0;

                    if (w_dims_valid && w_addr_ready == 0) begin
                         if (calc_match_found) begin
                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                            if (lut_valid_cnt[calc_match_index] < 2)
                                lut_valid_cnt[calc_match_index] <= lut_valid_cnt[calc_match_index] + 1;
                        end 
                        else begin
                            if (lut_count < MAX_TYPES) begin
                                lut_m[lut_count] <= i_dim_m; lut_n[lut_count] <= i_dim_n;
                                lut_start_addr[lut_count] <= free_ptr;
                                lut_idx[lut_count] <= 1; lut_valid_cnt[lut_count] <= 1;
                                free_ptr <= free_ptr + (single_mat_size << 1);
                                lut_count <= lut_count + 1;
                            end
                        end
                    end
                    if (w_rx_done) w_en_input <= 0;
                end
                
                S_MENU_DISP_GET_DIM: begin
                    w_en_input <= 1; w_task_mode <= 0; w_base_addr_to_input <= free_ptr;
                    led <= 8'b0001_0000;
                    if (w_dims_valid) w_addr_ready <= 1; else w_addr_ready <= 0;
                    if (w_rx_done) w_en_input <= 0;
                end
                S_MENU_DISP_SHOW: begin
                    w_en_display <= 1; w_disp_mode <= 0;
                    if (w_disp_done) w_en_display <= 0;
                end

                // --- 计算模式 ---
                S_CALC_SELECT_OP: begin
                    led <= 8'b0000_1000;
                    r_op_code <= sw[7:5]; w_op_code <= sw[7:5];
                    if (sw[7:5] == 3'b000) r_target_stage <= 0; else r_target_stage <= 1; 
                    r_stage <= 0; w_logic_error <= 0; // 清除之前的错误
                end
                S_CALC_SHOW_SUMMARY: begin
                    w_en_display <= 1; w_disp_mode <= 2;
                    if (w_disp_done) w_en_display <= 0;
                end

                S_CALC_GET_DIM: begin
                    w_en_input <= 1; w_task_mode <= 1; 
                    // 【修改】如果之前因为查不到而报错，现在用户一旦开始重新输入成功(valid)，就清除错误
                    if (w_dims_valid) begin 
                        w_en_input <= 0; 
                        w_logic_error <= 0; // 清除逻辑错误
                    end
                end

                S_CALC_FILTER: begin
                    r_hit_found <= 0; r_hit_type_idx <= 0;
                    for (i=0; i<MAX_TYPES; i=i+1) begin
                        if (i < lut_count && lut_m[i] == i_dim_m && lut_n[i] == i_dim_n && lut_valid_cnt[i] > 0) begin
                            r_hit_found <= 1; r_hit_type_idx <= i[1:0]; 
                        end
                    end
                end

                S_CALC_SHOW_LIST: begin
                    // 【修改】如果查不到矩阵，拉高逻辑错误标志，让 Top 倒计时
                    if (r_hit_found == 0) begin
                        w_logic_error <= 1; // 报错！
                        // 状态机会跳回 GET_DIM
                    end
                    else begin
                        w_en_display <= 1; w_disp_mode <= 1;
                        if (w_disp_done) w_en_display <= 0;
                    end
                end

                S_CALC_GET_ID: begin
                    w_en_input <= 1; w_task_mode <= 2;
                    if (w_id_valid) begin
                        if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx]) begin
                            // 输入正确
                            w_logic_error <= 0; // 清除错误
                            r_selected_id <= i_input_id_val[1:0];
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op1_m <= lut_m[r_hit_type_idx]; w_op1_n <= lut_n[r_hit_type_idx];
                                r_op1_m <= i_dim_m; r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op2_m <= lut_m[r_hit_type_idx]; w_op2_n <= lut_n[r_hit_type_idx];
                                r_op2_m <= i_dim_m; r_op2_n <= i_dim_n;
                            end
                            w_en_input <= 0;
                        end
                        else begin
                            // 【修改】ID 越界逻辑错误 -> 拉高标志，触发倒计时
                            w_logic_error <= 1;
                        end
                    end
                end

                S_CALC_SHOW_MAT: begin
                    w_en_display <= 1; w_disp_mode <= 3; w_disp_selected_id <= r_selected_id;
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        if (r_stage < r_target_stage) r_stage <= r_stage + 1;
                    end
                end
                
                // EXECUTE, RES_SHOW, WAIT_DECISION, ERROR 保持不变 ...
                S_CALC_EXECUTE: begin
                    w_start_calc <= 1; w_op_code <= r_op_code; w_res_addr <= calc_final_addr;
                    if (r_op_code == 3'b000) begin r_res_m <= r_op1_n; r_res_n <= r_op1_m; end
                    else if (r_op_code == 3'b010) begin r_res_m <= r_op1_m; r_res_n <= r_op2_n; end
                    else begin r_res_m <= r_op1_m; r_res_n <= r_op1_n; end
                    if (w_calc_done) begin
                        w_start_calc <= 0;
                        if (calc_match_found) begin
                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                            if (lut_valid_cnt[calc_match_index] < 2) lut_valid_cnt[calc_match_index] <= lut_valid_cnt[calc_match_index] + 1;
                        end 
                        else begin
                            if (lut_count < MAX_TYPES) begin
                                lut_m[lut_count] <= r_res_m; lut_n[lut_count] <= r_res_n;
                                lut_start_addr[lut_count] <= free_ptr; 
                                lut_valid_cnt[lut_count] <= 1; lut_idx[lut_count] <= 1;
                                free_ptr <= free_ptr + (r_res_m * r_res_n * 2);
                                lut_count <= lut_count + 1;
                            end
                        end
                    end
                end
                S_CALC_RES_SHOW: begin
                    w_en_display <= 1; w_disp_mode <= 0; 
                    if (w_disp_done) w_en_display <= 0;
                end
                S_WAIT_DECISION: led <= 8'b1000_0000;
                S_ERROR: led <= 8'b1111_1111;
            endcase
        end
    end

endmodule