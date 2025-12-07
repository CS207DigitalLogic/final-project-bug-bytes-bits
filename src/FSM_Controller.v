module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // 1. 物理接口 
    input wire [7:0] sw,      // sw[1:0] 模式选择, sw[7:5] 运算类型选择
    input wire [4:0] btn,     // btn[0] 确认键
    output reg [7:0] led,     // 状态/报错指示

    // 2. Input Subsystem 交互接口
    input wire w_dims_valid,  // Input: 维度读取完成 / 请求分配
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

    // 3. Display Subsystem 交互接口 
    input wire w_disp_done,       // Display: 展示完成
    output reg w_en_display,      // FSM: 启动展示
    // 0=单矩阵(回显), 1=列表(选数), 2=汇总(主菜单)
    output reg [1:0] w_disp_mode, 
    // 【新增】告诉 Display 这一类矩阵的信息
    output reg [7:0] w_disp_base_addr, // 起始基地址
    output reg [1:0] w_disp_total_cnt, // 总个数 (0,1,2)
    output reg [31:0] w_disp_m,   // 维度 M
    output reg [31:0] w_disp_n,   // 维度 N
    // 单矩阵展示时的目标地址 (复用 w_disp_base_addr 也可以，为了清晰保留这个)
    output reg [7:0] w_disp_target_addr, 

    // 4. Calculator Core 交互接口
    input wire w_calc_done,       // Calc: 计算完成
    output reg w_start_calc,      // FSM: 启动计算
    output reg [2:0] w_op_code,   // 运算类型
    output reg [7:0] w_op1_addr,  // 操作数1地址
    output reg [7:0] w_op2_addr,  // 操作数2地址
    output reg [7:0] w_res_addr,  // 结果存放地址
    
    // 调试
    output reg [3:0] w_state
);

    // 参数定义
    localparam S_IDLE        = 4'd0;
    localparam S_INPUT_MODE  = 4'd1; 
    localparam S_GEN_MODE    = 4'd2; 
    
    // 计算流程状态
    localparam S_CALC_SELECT_OP = 4'd3; 
    localparam S_CALC_GET_DIM   = 4'd4; 
    localparam S_CALC_FILTER    = 4'd5; // 查表筛选
    localparam S_CALC_SHOW_LIST = 4'd6; // 显示列表
    localparam S_CALC_GET_ID    = 4'd7; // 读ID (1或2)
    localparam S_CALC_SHOW_MAT  = 4'd8; // 回显确认
    localparam S_CALC_EXECUTE   = 4'd9; 
    
    localparam S_ERROR       = 4'd15;

    localparam MAX_TYPES = 4;

    // 内部寄存器
    reg [3:0] current_state, next_state; 

    // MMU 账本 
    reg [31:0] lut_m [0:MAX_TYPES-1];     
    reg [31:0] lut_n [0:MAX_TYPES-1];
    reg [7:0]  lut_start_addr [0:MAX_TYPES-1];
    reg        lut_idx [0:MAX_TYPES-1]; 
    reg [1:0]  lut_valid_cnt [0:MAX_TYPES-1]; 
    reg [2:0]  lut_count;
    reg [7:0]  free_ptr;

    // 计算上下文
    reg [2:0] r_op_code;    
    reg       r_stage;      
    reg       r_target_stage; 
    
    // 筛选结果寄存器
    reg [1:0] r_hit_type_idx; // 命中了账本的哪一行 (0~3)
    reg       r_hit_found;    // 是否找到匹配项
    
    reg [7:0] r_op1_addr;   
    reg [31:0] r_op1_m, r_op1_n; 

    // 按键消抖 
    reg btn_d0, btn_d1;
    wire btn_confirm_pose;
    assign btn_confirm_pose = btn_d0 & ~btn_d1;

    // 1. 组合逻辑：MMU 查表与地址计算
    reg       calc_match_found;
    reg [2:0] calc_match_index;
    reg [7:0] calc_final_addr;
    reg [7:0] single_mat_size;
    integer i;

    always @(*) begin
        calc_match_found = 0;
        calc_match_index = 0;
        calc_final_addr  = 0;
        single_mat_size  = (i_dim_m * i_dim_n); // 纯数据大小

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

    // 2. 时序逻辑：主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            lut_count <= 0; free_ptr <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0;
            w_addr_ready <= 0;
        end 
        else begin
            btn_d0 <= btn[0];
            btn_d1 <= btn_d0;
            w_addr_ready <= 0; 
            w_start_calc <= 0;

            case (current_state)
                S_IDLE: begin
                    w_en_input <= 0; w_en_display <= 0;
                    led <= 8'b0000_0001;
                    
                    if (btn_confirm_pose) begin
                        case (sw[1:0])
                            2'b00: current_state <= S_INPUT_MODE;
                            2'b01: current_state <= S_GEN_MODE;
                            2'b10: current_state <= S_CALC_SELECT_OP;
                        endcase
                    end
                end

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

                // 计算流程
                S_CALC_SELECT_OP: begin
                    r_op_code <= sw[7:5]; 
                    if (sw[7:5] == 3'b000) r_target_stage <= 0; 
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

                // 筛选逻辑: 查找匹配的规格索引
                S_CALC_FILTER: begin
                    r_hit_found <= 0;
                    r_hit_type_idx <= 0;

                    for (i=0; i<MAX_TYPES; i=i+1) begin
                        if (i < lut_count && lut_m[i] == i_dim_m && lut_n[i] == i_dim_n && lut_valid_cnt[i] > 0) begin
                            r_hit_found <= 1;
                            r_hit_type_idx <= i[1:0]; // 记录命中的行号
                        end
                    end
                    current_state <= S_CALC_SHOW_LIST;
                end

                // 显示列表: 将查到的基地址和数量传给 Display
                S_CALC_SHOW_LIST: begin
                    // 如果没找到匹配的，报错
                    if (r_hit_found == 0) begin
                         current_state <= S_ERROR;
                    end
                    else begin
                        w_en_display <= 1;
                        w_disp_mode <= 1;   // 列表模式 (List)
                        
                        // 传参给 Display
                        w_disp_m <= i_dim_m;
                        w_disp_n <= i_dim_n;
                        w_disp_base_addr <= lut_start_addr[r_hit_type_idx];
                        w_disp_total_cnt <= lut_valid_cnt[r_hit_type_idx];
                        
                        if (w_disp_done) begin
                            w_en_display <= 0;
                            current_state <= S_CALC_GET_ID;
                        end
                    end
                end

                // 读 ID: 直接判断 1 或 2
                S_CALC_GET_ID: begin
                    w_en_input <= 1;
                    w_task_mode <= 2; // Mode 2: Read ID
                    
                    if (w_id_valid) begin
                        // 检查合法性: 输入值必须 <= 现有的数量 (且>0)
                        if (i_input_id_val > 0 && i_input_id_val <= lut_valid_cnt[r_hit_type_idx]) begin
                            
                            // 计算物理地址: Base + (ID-1)*Size
                            // i_input_id_val 是 1 或 2
                            // (ID-1) 就是 0 或 1
                            
                            // 临时计算目标地址
                            // 这里假设 single_mat_size 仍然保持为 (m*n)
                            // 注意：i_dim_m 和 i_dim_n 此时仍是有效的
                            
                            w_disp_target_addr <= lut_start_addr[r_hit_type_idx] + 
                                                ((i_input_id_val - 1) * (i_dim_m * i_dim_n));

                            // 记录到操作数寄存器
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[r_hit_type_idx] + 
                                              ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                r_op1_m <= i_dim_m;
                                r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[r_hit_type_idx] + 
                                              ((i_input_id_val - 1) * (i_dim_m * i_dim_n));
                                // 这里可以加 m1==m2 的校验
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
                    w_disp_mode <= 0; // 单矩阵内容模式 (Single)
                    w_disp_m <= r_op1_m; // 确保使用正确的维度
                    w_disp_n <= r_op1_n;
                    // w_disp_target_addr 在上一步已经算好了
                    
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
                    w_res_addr <= free_ptr; 
                    
                    if (w_calc_done) begin
                        w_start_calc <= 0;
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