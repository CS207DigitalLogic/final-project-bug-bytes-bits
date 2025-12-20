module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // --- 物理接口 ---
    input wire [7:0] sw,
    input wire [4:0] btn,     // btn[0]:确认, btn[1]:重试, btn[2]:返回菜单
    output reg [7:0] led,

    // --- Input Subsystem ---
    input wire w_dims_valid,  
    input wire [31:0] i_dim_m,
    input wire [31:0] i_dim_n,
    input wire w_rx_done,     
    input wire w_error_flag,  
    input wire w_timeout,     
    
    input wire [31:0] i_input_id_val, 
    input wire w_id_valid,            
    
    output reg w_en_input,    
    output reg w_is_gen_mode, 
    output reg [1:0] w_task_mode, 
    output reg w_addr_ready,  
    output reg [8:0] w_base_addr_to_input, 

    // --- Display Subsystem ---
    input wire w_disp_done,           
    input wire [4:0] i_disp_lut_idx_req, 
    
    output reg w_en_display,          
    output reg [2:0] w_disp_mode,     
    output reg [8:0] w_disp_base_addr,
    output reg [1:0] w_disp_total_cnt,
    output reg [31:0] w_disp_m,       
    output reg [31:0] w_disp_n,       
    output reg [1:0] w_disp_selected_id, 
    
    output wire [7:0] w_system_total_count, 
    output wire [4:0] w_system_types_count,
    output reg [8:0] w_disp_target_addr, 

    // --- Calculator Core ---
    input wire w_calc_done,       
    output reg w_start_calc,      
    output reg [2:0] w_op_code,  
    output reg [8:0] w_op1_addr,  
    output reg [8:0] w_op2_addr,  
    output reg [31:0] w_op1_m,
    output reg [31:0] w_op1_n,
    output reg [31:0] w_op2_m,
    output reg [31:0] w_op2_n,
    output reg [8:0] w_res_addr,  
    
    output wire [4:0] w_state,
    output reg w_logic_error 
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
    localparam S_CALC_GET_SCALAR   = 5'd10;
    localparam S_CALC_CHECK_VALID  = 5'd11;
    localparam S_CALC_GENERATION   = 5'd12;
    localparam S_CALC_GEN_SHOW     = 5'd13;
    localparam S_CALC_EXECUTE      = 5'd14;
    localparam S_CALC_RES_SHOW     = 5'd15;
    localparam S_CALC_ERROR_RESET  = 5'd16;
    localparam S_CALC_WAIT_TIME    = 5'd17;
    localparam S_MENU_DISP_GET_DIM = 5'd18;
    localparam S_MENU_DISP_FILTER  = 5'd19;
    localparam S_MENU_DISP_SHOW    = 5'd20;
    localparam S_ERROR             = 5'd21;
    localparam S_WAIT_DECISION     = 5'd22;

    localparam MAX_TYPES = 25;

    reg [4:0] current_state, next_state;
    
    // MMU 账本
    reg [31:0] lut_m [0:MAX_TYPES-1];
    reg [31:0] lut_n [0:MAX_TYPES-1];
    reg [8:0]  lut_start_addr [0:MAX_TYPES-1];
    reg        lut_idx [0:MAX_TYPES-1];
    reg [1:0]  lut_valid_cnt [0:MAX_TYPES-1];
    reg [4:0]  lut_count;
    reg [8:0]  free_ptr;

    // 上下文
    reg [2:0] r_op_code;
    reg [1:0] r_stage;
    reg       r_target_stage;
    reg [4:0] r_hit_type_idx; 
    reg       r_hit_found;
    reg [1:0] r_selected_id;  
    
    reg [31:0] r_scalar_val; // 标量寄存器

    reg [8:0]  r_op1_addr, r_op2_addr;
    reg [31:0] r_op1_m, r_op1_n; 
    reg [31:0] r_op2_m, r_op2_n; 
    reg [31:0] r_res_m, r_res_n;
    reg [4:0] r_retry_state;

    reg       r_alloc_active;     // 1=已分配但未完成输入，0=空闲或已完成
    reg       r_alloc_is_new;     // 1=是新创建的矩阵，0=是覆盖旧矩阵
    reg [4:0] r_alloc_idx;        // 记录操作的是哪个LUT索引
    reg [8:0] r_backup_free_ptr;  // 备份分配前的 free_ptr
    reg [1:0] r_backup_valid_cnt; // 备份覆盖前的 valid_cnt

    // 按键消抖寄存器
    reg btn0_d0, btn0_d1;
    reg btn1_d0, btn1_d1;
    reg btn2_d0, btn2_d1;

    wire btn0_f, btn1_f, btn2_f;

    button_debouncer ubtn0(.clk(clk), .rst_n(rst_n), .key_in(btn[0]), .key_flag(btn0_f));
    button_debouncer ubtn1(.clk(clk), .rst_n(rst_n), .key_in(btn[1]), .key_flag(btn1_f));
    button_debouncer ubtn2(.clk(clk), .rst_n(rst_n), .key_in(btn[2]), .key_flag(btn2_f));

    wire btn_confirm_pose;
    wire btn_retry_pose;
    wire btn_menu_pose;   

    assign btn_confirm_pose = btn0_d0 & ~btn0_d1;
    assign btn_retry_pose   = btn1_d0 & ~btn1_d1;
    assign btn_menu_pose    = btn2_d0 & ~btn2_d1; 

    // 检测输入数据是否合法

    reg chk_valid_done;

    // 随机生成运算数模式

    reg is_calc_gen_mode;
    reg chk_generation_done;
    reg chk_disp_done;
    reg [4:0] has_m, has_n;
    reg [24:0] has;

    reg random_error_flag;

    reg [31:0] lfsr_reg;
    wire [31:0] random_val;
    assign random_val = lfsr_reg[31:0] % 10;

    always @(posedge clk) begin 
        if (!rst_n) lfsr_reg <= 32'hACE1;
        else lfsr_reg <= {lfsr_reg[30:0], lfsr_reg[31] ^ lfsr_reg[21] ^ lfsr_reg[1]};
    end

    // =========================================================================
    // 0. 辅助组合逻辑 
    // =========================================================================
    reg       calc_match_found;
    reg [4:0] calc_match_index;
    reg [8:0] calc_final_addr;
    reg [8:0] single_mat_size;
    integer i;
    reg [31:0] calc_pred_m, calc_pred_n;
    reg [31:0] search_m, search_n;
    reg        enable_search;

    always @(*) begin
        calc_pred_m = 0; calc_pred_n = 0;
        case (r_op_code)
            3'b000: begin      // Transpose
                calc_pred_m = r_op1_n; calc_pred_n = r_op1_m;
            end 
            3'b001: begin                    // Add 
                calc_pred_m = r_op1_m; calc_pred_n = r_op1_n;
            end
            3'b010: begin // Scalar Mul
                calc_pred_m = r_op1_m; calc_pred_n = r_op1_n; 
            end
            3'b011: begin //MatMul
                calc_pred_m = r_op1_m; calc_pred_n = r_op2_n; 
            end
            default: begin
                calc_pred_m = r_op1_m; calc_pred_n = r_op2_n; 
            end
        endcase
    end

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
                        calc_match_index = i[4:0];
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

    always @(*) begin
        // 1. 默认值
        w_disp_m = 0; w_disp_n = 0; w_disp_total_cnt = 0; w_disp_base_addr = 0;
        // 2. 根据状态或模式选择输出
        if (w_disp_mode == 2) begin 
            // 汇总模式 
            w_disp_m = lut_m[i_disp_lut_idx_req];
            w_disp_n = lut_n[i_disp_lut_idx_req];
            w_disp_total_cnt = lut_valid_cnt[i_disp_lut_idx_req];
            w_disp_base_addr = 0;
        end 
        else if (current_state == S_CALC_RES_SHOW) begin
            // 结果显示 
            w_disp_m = r_res_m;
            w_disp_n = r_res_n;
            w_disp_total_cnt = 1; w_disp_base_addr = w_res_addr;
        end
        else if (current_state == S_MENU_DISP_SHOW) begin
            // 菜单显示 
            w_disp_m = i_dim_m;
            w_disp_n = i_dim_n;
            w_disp_total_cnt = 1; w_disp_base_addr = free_ptr;
        end
        
        else if (current_state == S_CALC_GEN_SHOW) begin
            w_disp_total_cnt = 1; 
            if (r_stage == 0) begin
                // 展示 Op1
                w_disp_m = r_op1_m;
                w_disp_n = r_op1_n;
                w_disp_base_addr = r_op1_addr;
            end 
            else begin
                if (r_op_code == 3'b010) begin // 如果是标量乘法
                    w_disp_m = r_scalar_val;   // 把标量值传给 w_disp_m
                    w_disp_n = 0;              // 其他清零
                    w_disp_base_addr = 0;
                end else begin                 // 正常的矩阵 Op2
                    w_disp_m = r_op2_m;
                    w_disp_n = r_op2_n;
                    w_disp_base_addr = r_op2_addr;
                end
            end
        end

        else begin 
            // 默认列表模式/详情模式 
            w_disp_m = lut_m[r_hit_type_idx];
            w_disp_n = lut_n[r_hit_type_idx];
            w_disp_total_cnt = lut_valid_cnt[r_hit_type_idx];
            w_disp_base_addr = lut_start_addr[r_hit_type_idx];
        end
    end

    assign w_system_types_count = lut_count; 
    reg [7:0] total_cnt_sum;
    integer k;
    always @(*) begin
        total_cnt_sum = 0;
        for(k=0; k<MAX_TYPES; k=k+1) begin
            if(k < lut_count) total_cnt_sum = total_cnt_sum + lut_valid_cnt[k];
        end
    end
    assign w_system_total_count = total_cnt_sum;
    assign w_state = current_state;

    // =========================================================================
    // Stage 1: 状态跳转
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    // =========================================================================
    // Stage 2: 次态逻辑 
    // =========================================================================
    always @(*) begin
        next_state = current_state;

        if (current_state != S_IDLE && btn_menu_pose) begin
            next_state = S_IDLE;
        end
        else begin
            case (current_state)
                S_IDLE: begin
                    if (btn_confirm_pose) begin
                        case (sw[1:0])
                            2'b00: next_state = S_INPUT_MODE;// 1.开关调成00 按确认键跳转
                            2'b01: next_state = S_GEN_MODE;
                            2'b10: next_state = S_CALC_SELECT_OP;
                            2'b11: next_state = S_MENU_DISP_GET_DIM;
                        endcase
                    end
                end

                S_INPUT_MODE, S_GEN_MODE: begin
                    if (w_rx_done) next_state = S_WAIT_DECISION;// 等待输入完成跳转
                    else if (w_timeout) next_state = S_ERROR;
                end

                S_MENU_DISP_GET_DIM: begin
                    if (w_rx_done) next_state = S_MENU_DISP_SHOW;
                    else if (w_timeout) next_state = S_ERROR;
                end

                S_MENU_DISP_SHOW: begin
                    if (w_disp_done) next_state = S_WAIT_DECISION;
                end

                S_CALC_SELECT_OP: begin
                    if (btn_confirm_pose) next_state = S_CALC_SHOW_SUMMARY;
                end

                S_CALC_SHOW_SUMMARY: begin
                    if (w_disp_done) begin
                        if (is_calc_gen_mode) next_state=S_CALC_GENERATION;
                        else next_state = S_CALC_GET_DIM;
                    end
                end

                S_CALC_GET_DIM: begin
                    if (w_logic_error) next_state = S_CALC_ERROR_RESET;
                    else if (w_dims_valid) next_state = S_CALC_FILTER;
                end

                S_CALC_FILTER: begin
                    next_state = S_CALC_SHOW_LIST;
                end

                S_CALC_SHOW_LIST: begin
                    if (r_hit_found == 0) next_state = S_CALC_GET_DIM; 
                    else if (w_disp_done) next_state = S_CALC_GET_ID;
                end

                S_CALC_GET_ID: begin
                    if (w_logic_error) next_state = S_CALC_ERROR_RESET;
                    else if (w_id_valid) begin
                        if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx])
                            next_state = S_CALC_SHOW_MAT;
                    end
                end

                S_CALC_SHOW_MAT: begin
                    if (w_disp_done) begin
                        if (r_stage < r_target_stage) begin
                            if (r_op_code == 3'b010) next_state = S_CALC_GET_SCALAR;
                            else next_state = S_CALC_GET_DIM;
                        end
                        else next_state = S_CALC_CHECK_VALID;
                    end
                end

                // Stage 2：读取标量 -> 等待按键
                S_CALC_GET_SCALAR: begin
                    // 只要按了确认键，就直接拿数据去计算
                    if (btn_confirm_pose) begin
                        next_state = S_CALC_CHECK_VALID;
                    end
                end

                S_CALC_CHECK_VALID: begin
                    if (w_logic_error) next_state=S_CALC_ERROR_RESET;
                    else if (chk_valid_done) next_state=S_CALC_EXECUTE;
                end

                S_CALC_GENERATION: begin
                    if (random_error_flag) next_state=S_ERROR;
                    else if (chk_generation_done) next_state=S_CALC_GEN_SHOW;
                end

                S_CALC_GEN_SHOW: begin
                    // 阶段 0: 展示 Op1
                    // 阶段 1: 展示 Op2 
                    // 阶段 2: 展示完毕，去执行
                    if (r_stage == 2) next_state = S_CALC_EXECUTE;
                    else next_state = S_CALC_GEN_SHOW; // 还没展示完，保持在当前状态
                end

                S_CALC_EXECUTE: begin
                    if (w_calc_done) next_state = S_CALC_RES_SHOW;
                end

                S_CALC_RES_SHOW: begin
                    if (w_disp_done) next_state = S_WAIT_DECISION;
                end

                S_CALC_ERROR_RESET: begin
                    next_state = S_CALC_WAIT_TIME;
                end

                S_CALC_WAIT_TIME: begin
                    if (w_timeout) next_state = S_ERROR;                    
                    else if (w_dims_valid) next_state = S_CALC_FILTER;
                    else if (w_logic_error) next_state = S_CALC_WAIT_TIME;
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
    end

    // =========================================================================
    // Stage 3: 数据输出与寄存器更新
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_count <= 0; free_ptr <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) has[i] <= 0;
            for(i=0; i<5; i=i+1) begin
                has_m[i] <= 0;
                has_n[i] <= 0;
            end
            w_is_gen_mode <= 0;
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0; w_addr_ready <= 0;
            r_res_m <= 0; r_res_n <= 0; led <= 0;
            w_op1_addr <= 0; w_op2_addr <= 0; w_res_addr <= 0;
            w_op1_m <= 0; w_op1_n <= 0; w_op2_m <= 0; w_op2_n <= 0;
            btn0_d0 <= 0; btn0_d1 <= 0; btn1_d0 <= 0; btn1_d1 <= 0;
            btn2_d0 <= 0; btn2_d1 <= 0; 
            r_retry_state <= S_IDLE;
            w_logic_error <= 0;
            r_scalar_val <= 0;
            chk_valid_done <= 0;
            chk_generation_done <= 0;
            is_calc_gen_mode <= 0;
            r_alloc_active <= 0;
            r_alloc_is_new <= 0;
            r_alloc_idx <= 0;
            r_backup_free_ptr <= 0;
            r_backup_valid_cnt <= 0;
            random_error_flag <= 0;
        end 
        else begin
            w_addr_ready <= 0; w_start_calc <= 0; w_is_gen_mode <= 0;

            btn0_d0 <= btn0_f; btn0_d1 <= btn0_d0;
            btn1_d0 <= btn1_f; btn1_d1 <= btn1_d0;
            btn2_d0 <= btn2_f; btn2_d1 <= btn2_d0; 
            
            chk_valid_done <= 0;
            chk_generation_done <= 0;

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
                    w_en_input <= 1;
                    w_task_mode <= 0;
                    w_is_gen_mode <= (current_state == S_GEN_MODE);
                    
                    if (w_error_flag) led <= 8'b1111_1111;
                    else if (w_is_gen_mode) led <= 8'b0000_0100;
                    else led <= 8'b0000_0010;
                    
                    if (w_dims_valid) begin
                        w_addr_ready <= 1;
                        if (w_addr_ready == 0)
                            w_base_addr_to_input <= calc_final_addr;
                    end else w_addr_ready <= 0;

                    if (w_dims_valid && w_addr_ready == 0) begin
                        r_alloc_active <= 1; 

                        if (calc_match_found) begin
                            r_alloc_is_new <= 0;
                            r_alloc_idx <= calc_match_index;
                            r_backup_valid_cnt <= lut_valid_cnt[calc_match_index]; // 备份旧的 valid_cnt

                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                            if (lut_valid_cnt[calc_match_index] < 2)
                                lut_valid_cnt[calc_match_index] <= lut_valid_cnt[calc_match_index] + 1;
                        end 
                        else begin
                            if (lut_count < MAX_TYPES) begin
                                r_alloc_is_new <= 1;
                                r_backup_free_ptr <= free_ptr; // 备份旧的 free_ptr

                                lut_m[lut_count] <= i_dim_m;
                                lut_n[lut_count] <= i_dim_n;
                                lut_start_addr[lut_count] <= free_ptr;
                                lut_idx[lut_count] <= 1; lut_valid_cnt[lut_count] <= 1;
                                free_ptr <= free_ptr + (single_mat_size << 1);
                                lut_count <= lut_count + 1;
                            end
                        end
                    end
                    if (w_rx_done) begin 
                        w_en_input <= 0;
                        r_alloc_active <= 0;
                        has_m[lut_m[lut_count-1]-1] <= 1;
                        has_n[lut_n[lut_count-1]-1] <= 1;
                        has[(lut_m[lut_count-1]-1)*5+lut_n[lut_count-1]-1] <= 1;
                    end
                    else if (w_error_flag) begin
                        if (r_alloc_active) begin
                            r_alloc_active <= 0;
                            if (r_alloc_is_new) begin
                                lut_count <= lut_count - 1;
                                free_ptr <= r_backup_free_ptr;
                            end else begin
                                lut_idx[r_alloc_idx] <= ~lut_idx[r_alloc_idx]; 
                                lut_valid_cnt[r_alloc_idx] <= r_backup_valid_cnt; 
                            end
                        end
                    end
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

                S_CALC_SELECT_OP: begin
                    led <= 8'b0000_1000;
                    r_op_code <= sw[7:5]; w_op_code <= sw[7:5];
                    is_calc_gen_mode <= sw[3];
                    chk_generation_done <= 0;
                    if (sw[7:5] == 3'b000) r_target_stage <= 0; else r_target_stage <= 1; 
                    r_stage <= 0; w_logic_error <= 0; 
                end
                S_CALC_SHOW_SUMMARY: begin
                    w_en_display <= 1; w_disp_mode <= 2;
                    if (w_disp_done) w_en_display <= 0;
                end

                S_CALC_GET_DIM: begin
                    w_en_input <= 1; w_task_mode <= 1; 
                    if (w_dims_valid) begin 
                        w_en_input <= 0; 
                        w_logic_error <= 0; 
                    end
                end

                S_CALC_FILTER: begin
                    led <= 8'b0000_1000;
                    r_hit_found <= 0; r_hit_type_idx <= 0;
                    for (i=0; i<MAX_TYPES; i=i+1) begin
                        if (i < lut_count && lut_m[i] == i_dim_m && lut_n[i] == i_dim_n && lut_valid_cnt[i] > 0) begin
                            r_hit_found <= 1; r_hit_type_idx <= i[4:0]; 
                        end
                    end
                end

                S_CALC_SHOW_LIST: begin
                    if (r_hit_found == 0) begin
                        w_logic_error <= 1; 
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
                            w_logic_error <= 0; 
                            r_selected_id <= i_input_id_val[1:0];
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                r_op1_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op1_m <= lut_m[r_hit_type_idx]; w_op1_n <= lut_n[r_hit_type_idx];
                                r_op1_m <= i_dim_m; r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                r_op2_addr <= lut_start_addr[r_hit_type_idx] + ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                w_op2_m <= lut_m[r_hit_type_idx]; w_op2_n <= lut_n[r_hit_type_idx];
                                r_op2_m <= i_dim_m; r_op2_n <= i_dim_n;
                            end
                            w_en_input <= 0;
                        end
                        else begin
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

                S_CALC_GET_SCALAR: begin
                    // 1. 关闭 Input 模块
                    w_en_input <= 0; 
                    w_logic_error <= 0;
                    
                    // 2. 将当前拨码开关的值显示在 LED 上供用户确认 (sw[7:4])
                    led <= {4'b0000, sw[7:4]};

                    // 3. 按下确认键时，锁存数据
                    if (btn_confirm_pose) begin
                        r_scalar_val <= {28'd0, sw[7:4]}; 
                    end
                end

                S_CALC_CHECK_VALID: begin
                    w_logic_error<=0;
                    case (r_op_code)
                        3'b000: chk_valid_done<=1;
                        3'b001: begin
                            if (r_op1_m==r_op2_m && r_op1_n==r_op2_n)
                                chk_valid_done<=1;
                            else
                                w_logic_error<=1;
                        end
                        3'b010: chk_valid_done<=1;
                        3'b011: begin
                            if (r_op1_n==r_op2_m)
                                chk_valid_done<=1;
                            else
                                w_logic_error<=1;
                        end
                        default: begin
                            if (r_op1_n==r_op2_m)
                                chk_valid_done<=1;
                            else
                                w_logic_error<=1;
                        end
                    endcase
                end
                
                S_CALC_GENERATION: begin
                    random_error_flag <= 0;
                    chk_generation_done <= 0;
                    if (lut_count==0) random_error_flag <= 1;
                    else begin
                        case (r_op_code)
                            3'b000: begin
                                r_op1_m <= lut_m[lfsr_reg[31:0]%lut_count];
                                r_op1_n <= lut_n[lfsr_reg[31:0]%lut_count];
                                if (lut_valid_cnt[lfsr_reg[31:0]%lut_count]==1)
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count];
                                else
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count]+
                                        lfsr_reg[31:31]*lut_m[lfsr_reg[31:0]%lut_count]*lut_n[lfsr_reg[31:0]%lut_count];
                                chk_generation_done <= 1; r_stage <= 0;
                            end
                            3'b001: begin
                                r_op1_m <= lut_m[lfsr_reg[31:0]%lut_count];
                                r_op1_n <= lut_n[lfsr_reg[31:0]%lut_count];
                                if (lut_valid_cnt[lfsr_reg[31:0]%lut_count]==1)
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count];
                                else
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count]+
                                        lfsr_reg[31:31]*lut_m[lfsr_reg[31:0]%lut_count]*lut_n[lfsr_reg[31:0]%lut_count];
                                chk_generation_done <= 1;r_stage <= 0;
                                r_op2_m <= lut_m[lfsr_reg[31:0]%lut_count];
                                r_op2_n <= lut_n[lfsr_reg[31:0]%lut_count];
                                if (lut_valid_cnt[lfsr_reg[31:0]%lut_count]==1)
                                    r_op2_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count];
                                else
                                    r_op2_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count]+
                                        lfsr_reg[30:30]*lut_m[lfsr_reg[31:0]%lut_count]*lut_n[lfsr_reg[31:0]%lut_count];
                            end
                            3'b010: begin
                                r_op1_m <= lut_m[lfsr_reg[31:0]%lut_count];
                                r_op1_n <= lut_n[lfsr_reg[31:0]%lut_count];
                                if (lut_valid_cnt[lfsr_reg[31:0]%lut_count]==1)
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count];
                                else
                                    r_op1_addr <= lut_start_addr[lfsr_reg[31:0]%lut_count]+
                                        lfsr_reg[31:31]*lut_m[lfsr_reg[31:0]%lut_count]*lut_n[lfsr_reg[31:0]%lut_count];
                                r_scalar_val <= random_val;
                                chk_generation_done <= 1;r_stage <= 0;
                            end
                            3'b011: begin
                                if ((!has_m[4] || !has_n[4]) && (!has_m[3] || !has_n[3]) && (!has_m[2] || !has_n[2])
                                    && (!has_m[1] || !has_n[1]) && (!has_m[0] || !has_n[0]))
                                    random_error_flag <= 1;
                                if (has_m[lfsr_reg[9:0]%5] && has_n[lfsr_reg[9:0]%5]) begin
                                    if (has[lfsr_reg[19:10]%5*5+lfsr_reg[9:0]%5]) begin
                                        if (has[lfsr_reg[9:0]%5*5+lfsr_reg[29:20]%5]) begin
                                            r_op1_m <= lfsr_reg[19:10]%5+1;
                                            r_op1_n <= lfsr_reg[9:0]%5+1;
                                            r_op2_m <= lfsr_reg[9:0]%5+1;
                                            r_op2_n <= lfsr_reg[29:20]%5+1;
                                            for(i=0; i<MAX_TYPES; i=i+1) begin
                                                if (i<lut_count) begin
                                                    if (lut_m[i]==lfsr_reg[19:10]%5+1 && lut_n[i]==lfsr_reg[9:0]%5+1) begin
                                                        if (lut_valid_cnt[i]==1)
                                                            r_op1_addr <= lut_start_addr[i];
                                                        else
                                                            r_op1_addr <= lut_start_addr[i]+
                                                                lfsr_reg[31:31]*lut_m[i]*lut_n[i];
                                                    end
                                                    if (lut_m[i]==lfsr_reg[9:0]%5+1 && lut_n[i]==lfsr_reg[29:20]%5+1) begin
                                                        if (lut_valid_cnt[i]==1)
                                                            r_op2_addr <= lut_start_addr[i];
                                                        else
                                                            r_op2_addr <= lut_start_addr[i]+
                                                                lfsr_reg[30:30]*lut_m[i]*lut_n[i];
                                                    end
                                                end
                                            end
                                            chk_generation_done<=1;r_stage <= 0;
                                        end
                                    end
                                end
                            end
                            default: begin
                                if ((!has_m[4] || !has_n[4]) && (!has_m[3] || !has_n[3]) && (!has_m[2] || !has_n[2])
                                    && (!has_m[1] || !has_n[1]) && (!has_m[0] || !has_n[0]))
                                    random_error_flag <= 1;
                                if (has_m[lfsr_reg[9:0]%5] && has_n[lfsr_reg[9:0]%5]) begin
                                    if (has[lfsr_reg[19:10]%5*5+lfsr_reg[9:0]%5]) begin
                                        if (has[lfsr_reg[9:0]%5*5+lfsr_reg[29:20]%5]) begin
                                            r_op1_m <= lfsr_reg[19:10]%5+1;
                                            r_op1_n <= lfsr_reg[9:0]%5+1;
                                            r_op2_m <= lfsr_reg[9:0]%5+1;
                                            r_op2_n <= lfsr_reg[29:20]%5+1;
                                            for(i=0; i<MAX_TYPES; i=i+1) begin
                                                if (i<lut_count) begin
                                                    if (lut_m[i]==lfsr_reg[19:10]%5+1 && lut_n[i]==lfsr_reg[9:0]%5+1) begin
                                                        if (lut_valid_cnt[i]==1)
                                                            r_op1_addr <= lut_start_addr[i];
                                                        else
                                                            r_op1_addr <= lut_start_addr[i]+
                                                                lfsr_reg[31:31]*lut_m[i]*lut_n[i];
                                                    end
                                                    if (lut_m[i]==lfsr_reg[9:0]%5+1 && lut_n[i]==lfsr_reg[29:20]%5+1) begin
                                                        if (lut_valid_cnt[i]==1)
                                                            r_op2_addr <= lut_start_addr[i];
                                                        else
                                                            r_op2_addr <= lut_start_addr[i]+
                                                                lfsr_reg[30:30]*lut_m[i]*lut_n[i];
                                                    end
                                                end
                                            end
                                            chk_generation_done<=1;r_stage <= 0;
                                        end
                                    end
                                end
                            end
                        endcase
                    end
                end


                S_CALC_GEN_SHOW: begin
                    case (r_stage)
                        0: begin 
                            if (w_disp_done) begin
                                if (w_en_display) begin
                                    w_en_display <= 0;
                                    r_stage <= 1; 
                                end
                            end
                            else begin
                                w_en_display <= 1;
                                w_disp_mode  <= 0;
                            end
                        end


                        1: begin 
                            if (r_op_code == 3'b000) begin
                                r_stage <= 2;
                                // 转置
                            end
                            else if (r_op_code == 3'b010) begin
                                // 标量乘法展示逻辑
                                if (w_disp_done) begin
                                    if (w_en_display) begin
                                        w_en_display <= 0;
                                        r_stage <= 2;
                                    end
                                end
                                else begin
                                    w_en_display <= 1;
                                    w_disp_mode  <= 4; 
                                end
                            end
                        
                            else begin
                                if (w_disp_done) begin
                                    if (w_en_display) begin
                                        w_en_display <= 0;
                                        r_stage <= 2; 
                                    end
                                end
                                else begin
                                    w_en_display <= 1;
                                    w_disp_mode  <= 0; 
                                end
                            end
                        end

                        2: begin 
                            // 等待 Stage 2 跳转
                            w_en_display <= 0;
                        end
                    endcase
                end
                
                S_CALC_EXECUTE: begin
                    w_start_calc <= 1; w_op_code <= r_op_code; w_res_addr <= calc_final_addr;

                    w_op1_addr <= r_op1_addr;
                    w_op1_m    <= r_op1_m;
                    w_op1_n    <= r_op1_n;
                    
                    w_op2_addr <= r_op2_addr;
                    w_op2_m    <= r_op2_m;
                    w_op2_n    <= r_op2_n;

                    case(r_op_code)
                        3'b000: begin r_res_m <= r_op1_n; r_res_n <= r_op1_m; end
                        3'b001: begin r_res_m <= r_op1_m; r_res_n <= r_op1_n; end
                        3'b010: begin 
                            r_res_m <= r_op1_m; 
                            r_res_n <= r_op1_n; 
                            w_op2_m <= r_scalar_val; 
                        end
                        3'b011: begin  r_res_m=r_op1_m; r_res_n=r_op2_n; end
                        default: begin  r_res_m=r_op1_m; r_res_n=r_op2_n; end
                    endcase
                    
                    if (w_calc_done) begin
                        w_start_calc <= 0;
                        has_m[r_res_m-1] <= 1;
                        has_n[r_res_n-1] <= 1;
                        has[(r_res_m-1)*5+r_res_n-1] <= 1;
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
                S_CALC_ERROR_RESET: begin
                    r_stage <= 0;
                    w_en_input <= 0;
                end
                S_CALC_WAIT_TIME: begin
                    led <= 8'b1111_1111;
                    w_en_input <= 1; w_task_mode <= 1; 
                    if (w_dims_valid) begin 
                        w_en_input <= 0; 
                        w_logic_error <= 0; 
                    end
                end
                S_WAIT_DECISION: led <= 8'b1000_0000;
                S_ERROR: begin
                    w_en_input <= 0;
                    random_error_flag <= 0;
                    led <= 8'b1111_1111;
                end
            endcase
        end
    end

endmodule