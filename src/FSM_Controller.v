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
    input wire w_error_flag,  // Input: 出错
    
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
    output reg [7:0] w_res_addr,  // 结果存放地址 (需要FSM分配)
    
    // 调试端口
    output reg [3:0] w_state
);

    // =========================================================================
    // 参数定义
    // =========================================================================
    localparam S_IDLE           = 4'd0;
    localparam S_INPUT_MODE     = 4'd1; 
    localparam S_GEN_MODE       = 4'd2; 
    
    // 计算流程状态
    localparam S_CALC_SELECT_OP = 4'd3; 
    localparam S_CALC_GET_DIM   = 4'd4; 
    localparam S_CALC_FILTER    = 4'd5; // 查表筛选
    localparam S_CALC_SHOW_LIST = 4'd6; // 显示列表
    localparam S_CALC_GET_ID    = 4'd7; // 读ID (1或2)
    localparam S_CALC_SHOW_MAT  = 4'd8; // 回显确认
    localparam S_CALC_EXECUTE   = 4'd9; // 执行计算 & 登记
    localparam S_CALC_RES_SHOW  = 4'd10;// 结果展示
    // 主菜单-展示模式专用状态
    localparam S_MENU_DISP_GET_DIM = 4'd11;
    localparam S_MENU_DISP_FILTER  = 4'd12;
    localparam S_MENU_DISP_SHOW    = 4'd13;
    
    localparam S_ERROR          = 4'd15;

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
    // 1. 组合逻辑：MMU 查表与地址计算 (用于 Input/Gen 模式)
    // =========================================================================
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

    // =========================================================================
    // 2. 组合逻辑：Display 参数 MUX (核心控制)
    // =========================================================================
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
            // 直接使用 Input 模块当前的维度寄存器
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

    // =========================================================================
    // 3. 时序逻辑：主状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            lut_count <= 0; free_ptr <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0;
            w_addr_ready <= 0;
            // 复位寄存器
            r_res_m <= 0; r_res_n <= 0;
        end 
        else begin
            btn_d0 <= btn[0];
            btn_d1 <= btn_d0;
            w_addr_ready <= 0; 
            w_start_calc <= 0;

            case (current_state)
                // -----------------------------------------------------------
                // IDLE: 模式选择
                // -----------------------------------------------------------
                S_IDLE: begin
                    w_en_input <= 0; w_en_display <= 0;
                    led <= 8'b0000_0001;
                    
                    if (btn_confirm_pose) begin
                        case (sw[1:0])
                            2'b00: current_state <= S_INPUT_MODE;
                            2'b01: current_state <= S_GEN_MODE;
                            2'b10: current_state <= S_CALC_SELECT_OP;
                            2'b11: current_state <= S_MENU_DISP_GET_DIM;
                        endcase
                    end
                end

                // -----------------------------------------------------------
                // 基础模式: 存矩阵
                // -----------------------------------------------------------
                S_INPUT_MODE, S_GEN_MODE: begin
                    w_en_input <= 1;
                    w_task_mode <= 0; // Mode 0: 完整存储
                    w_is_gen_mode <= (current_state == S_GEN_MODE);

                    if (w_dims_valid && !w_addr_ready) begin
                        w_base_addr_to_input <= calc_final_addr;
                        w_addr_ready <= 1;

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
                        current_state <= S_IDLE;
                        w_en_input <= 0;
                    end
                end

                // -----------------------------------------------------------
                // 主菜单功能: 矩阵展示 (输入维度 -> 展示该维度所有矩阵)
                // -----------------------------------------------------------
                
                // 1. 让 Input 模块读取 m, n
                S_MENU_DISP_GET_DIM: begin
                    w_en_input <= 1;
                    w_task_mode <= 0;

                    w_base_addr_to_input <= free_ptr;
                    
                    // Input 模块握手逻辑 (Mode 0 需要先握手给地址)
                    if (w_dims_valid && !w_addr_ready) begin
                        w_addr_ready <= 1;
                    end
                    
                    // 等待 Input 模块全部接收完成 (w_rx_done)
                    if (w_rx_done) begin
                        w_en_input <= 0;
                        current_state <= S_MENU_DISP_SHOW;
                    end
                end

                // 2. 调用 Display 显示列表
                S_MENU_DISP_SHOW: begin
                    w_en_display <= 1;
                    w_disp_mode <= 0;   // ★ Mode 0: 单矩阵展示模式
                    
                    // 告诉 Display 去哪里读 (刚才 Input 存的地方)
                    w_disp_base_addr <= free_ptr; 
                    
                    // 告诉 Display 维度 (Input 模块刚读到的)
                    w_disp_m <= i_dim_m;
                    w_disp_n <= i_dim_n;
                    w_disp_total_cnt <= 1; // 只有一个矩阵
                    
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        // 展示完毕，直接回主菜单
                        // 注意：这里没有 update free_ptr，
                        // 所以下次操作会直接覆盖这个临时数据，非常节省空间
                        current_state <= S_IDLE;
                    end
                end

                // -----------------------------------------------------------
                // 计算流程
                // -----------------------------------------------------------
                S_CALC_SELECT_OP: begin
                    r_op_code <= sw[7:5]; 
                    if (sw[7:5] == 3'b000) r_target_stage <= 0; // 转置只需要1个
                    else r_target_stage <= 1; 
                    r_stage <= 0; 
                    
                    if (btn_confirm_pose) 
                        current_state <= S_CALC_GET_DIM;
                end

                S_CALC_GET_DIM: begin
                    w_en_input <= 1;
                    w_task_mode <= 1; // Mode 1: Query Dim
                    
                    if (w_dims_valid) begin
                        w_en_input <= 0;
                        current_state <= S_CALC_FILTER;
                    end
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
                    current_state <= S_CALC_SHOW_LIST;
                end

                S_CALC_SHOW_LIST: begin
                    if (r_hit_found == 0) begin
                         current_state <= S_ERROR;
                    end
                    else begin
                        w_en_display <= 1;
                        w_disp_mode <= 1; // List Mode
                        // MUX 已经处理了 w_disp_m 等参数的赋值
                        
                        if (w_disp_done) begin
                            w_en_display <= 0;
                            current_state <= S_CALC_GET_ID;
                        end
                    end
                end

                S_CALC_GET_ID: begin
                    w_en_input <= 1;
                    w_task_mode <= 2; // Mode 2: Read ID
                    
                    if (w_id_valid) begin
                        if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx]) begin
                            
                            r_selected_id <= i_input_id_val[1:0];

                            // 记录操作数信息 (物理地址 & 维度)
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[r_hit_type_idx] + 
                                              ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                r_op1_m <= i_dim_m;
                                r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[r_hit_type_idx] + 
                                              ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                r_op2_m <= i_dim_m;
                                r_op2_n <= i_dim_n;
                            end

                            w_en_input <= 0;
                            current_state <= S_CALC_SHOW_MAT;
                        end
                        else begin
                            current_state <= S_ERROR;
                        end
                    end
                end

                S_CALC_SHOW_MAT: begin
                    w_en_display <= 1;
                    w_disp_mode <= 3; // Mode 3: Cache Recall
                    w_disp_selected_id <= r_selected_id;
                    
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        
                        if (r_stage < r_target_stage) begin
                            r_stage <= r_stage + 1;
                            current_state <= S_CALC_GET_DIM; 
                        end
                        else begin
                            current_state <= S_CALC_EXECUTE; 
                        end
                    end
                end

                S_CALC_EXECUTE: begin
                    w_start_calc <= 1; 
                    w_op_code <= r_op_code;
                    w_res_addr <= free_ptr; // 分配结果存放地址
                    
                    // --- 预判结果维度 ---
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
                        
                        // --- 登记新矩阵到账本 ---
                        if (lut_count < MAX_TYPES) begin
                            lut_m[lut_count] <= r_res_m;
                            lut_n[lut_count] <= r_res_n;
                            lut_start_addr[lut_count] <= free_ptr; // 结果存在 free_ptr
                            lut_valid_cnt[lut_count] <= 1;
                            lut_idx[lut_count] <= 1;
                            
                            // 移动空闲指针
                            free_ptr <= free_ptr + (r_res_m * r_res_n);
                            lut_count <= lut_count + 1;
                        end
                        
                        current_state <= S_CALC_RES_SHOW; 
                    end
                end
                
                S_CALC_RES_SHOW: begin
                    w_en_display <= 1;
                    w_disp_mode <= 0; // Mode 0: 单矩阵展示 (Display直接读Storage)
                    // MUX 会根据 state==S_CALC_RES_SHOW 自动切换参数
                    
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        current_state <= S_IDLE;
                    end
                end

                S_ERROR: begin
                    led <= 8'b1111_1111;
                    if (btn_confirm_pose) current_state <= S_IDLE;
                end
            endcase
        end
    end
    
    always @(*) w_state = current_state;

endmodule