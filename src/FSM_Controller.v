module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // 1. 物理接口 
    input wire [7:0] sw,      // sw[1:0] 模式选择, sw[7:4] 运算类型选择(假设)
    input wire [4:0] btn,     // btn[0] 确认键
    output reg [7:0] led,     // 状态/报错指示

    // 2. Input Subsystem 交互接口
    input wire w_dims_valid,  // Input: 维度读取完成 (Mode 1) / 请求分配 (Mode 0)
    input wire [31:0] i_dim_m,// Input: 矩阵行数
    input wire [31:0] i_dim_n,// Input: 矩阵列数
    input wire w_rx_done,     // Input: 任务完成
    input wire w_error_flag,  // Input: 出错
    
    // [新增] Input 接口
    input wire [31:0] i_input_id_val, // Input: 读取到的ID (Mode 2)
    input wire w_id_valid,            // Input: ID读取完成
    
    output reg w_en_input,    // 启用 Input 模块
    output reg w_is_gen_mode, // 0=手动, 1=生成
    output reg [1:0] w_task_mode, // [新增] 0=存, 1=读维度, 2=读ID
    output reg w_addr_ready,  // FSM: 地址分配好了
    output reg [7:0] w_base_addr_to_input, // 分配好的基地址

    // 3. Display Subsystem 交互接口 (新增)
    input wire w_disp_done,       // Display: 展示完成
    output reg w_en_display,      // FSM: 启动展示
    output reg [1:0] w_disp_mode, // 0=列表摘要, 1=单矩阵内容
    output reg [7:0] w_disp_mask, // [位选] 仅展示哪些ID (用于Filter结果)
    output reg [7:0] w_disp_target_addr, // 单矩阵展示时的地址
    output reg [31:0] w_disp_m,   // 单矩阵展示时的维度
    output reg [31:0] w_disp_n,

    // 4. Calculator Core 交互接口 (新增)
    input wire w_calc_done,       // Calc: 计算完成
    output reg w_start_calc,      // FSM: 启动计算
    output reg [2:0] w_op_code,   // 运算类型
    output reg [7:0] w_op1_addr,  // 操作数1地址
    output reg [7:0] w_op2_addr,  // 操作数2地址
    output reg [7:0] w_res_addr,  // 结果存放地址 (需要FSM分配)
    
    // 调试
    output reg [3:0] w_state
);

    // =========================================================================
    // 参数定义
    // =========================================================================
    // 基础模式状态
    localparam S_IDLE        = 4'd0;
    localparam S_INPUT_MODE  = 4'd1; 
    localparam S_GEN_MODE    = 4'd2; 
    
    // 计算流程状态 (流水线)
    localparam S_CALC_SELECT_OP = 4'd3; // 选择加减乘除
    localparam S_CALC_GET_DIM   = 4'd4; // 让Input模块读 m, n
    localparam S_CALC_FILTER    = 4'd5; // 查表筛选
    localparam S_CALC_SHOW_LIST = 4'd6; // 让Display显示候选列表
    localparam S_CALC_GET_ID    = 4'd7; // 让Input模块读用户选的ID
    localparam S_CALC_SHOW_MAT  = 4'd8; // 回显确认矩阵
    localparam S_CALC_EXECUTE   = 4'd9; // 执行计算
    
    localparam S_ERROR       = 4'd15;

    localparam MAX_TYPES = 4;

    // =========================================================================
    // 内部寄存器
    // =========================================================================
    reg [3:0] current_state, next_state; // 这里建议改为 reg [4:0] 防止状态不够

    // --- MMU 账本 ---
    reg [31:0] lut_m [0:MAX_TYPES-1];     
    reg [31:0] lut_n [0:MAX_TYPES-1];
    reg [7:0]  lut_start_addr [0:MAX_TYPES-1];
    reg        lut_idx [0:MAX_TYPES-1]; 
    reg [1:0]  lut_valid_cnt [0:MAX_TYPES-1]; // [重要] 记录每种存了几个 (0,1,2)
    reg [2:0]  lut_count;
    reg [7:0]  free_ptr;

    // --- 计算上下文寄存器 ---
    reg [2:0] r_op_code;    // 当前运算类型
    reg       r_stage;      // 0=找第一个数, 1=找第二个数
    reg       r_target_stage; // 需要几个数? (转置=0, 加法=1)
    
    reg [7:0] r_match_mask; // 筛选结果 (Bitmask: ID 1~8)
    reg [7:0] r_op1_addr;   // 暂存操作数1
    reg [31:0] r_op1_m, r_op1_n; // 暂存操作数1维度 (用于检查加法同维度等)

    // --- 按键消抖 ---
    reg btn_d0, btn_d1;
    wire btn_confirm_pose;
    assign btn_confirm_pose = btn_d0 & ~btn_d1;

    // =========================================================================
    // 1. 组合逻辑：MMU 查表与地址计算
    // =========================================================================
    reg       calc_match_found;
    reg [2:0] calc_match_index;
    reg [7:0] calc_final_addr;
    reg [7:0] single_mat_size;
    integer i;

    always @(*) begin
        // ... (原有的Input查表逻辑保持不变) ...
        calc_match_found = 0;
        calc_match_index = 0;
        calc_final_addr  = 0;
        single_mat_size  = 2 + (i_dim_m * i_dim_n);

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
                // 命中: 根据 lut_idx 给地址
                if (lut_idx[calc_match_index] == 0)
                    calc_final_addr = lut_start_addr[calc_match_index];
                else
                    calc_final_addr = lut_start_addr[calc_match_index] + single_mat_size;
            end 
            else begin
                // 未命中: 给 free_ptr
                calc_final_addr = free_ptr;
            end
        end
    end

    // =========================================================================
    // 2. 时序逻辑：主状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            lut_count <= 0; free_ptr <= 0;
            // 清空 lut_valid_cnt
            for(i=0; i<MAX_TYPES; i=i+1) lut_valid_cnt[i] <= 0;
            // 清空 lut_idx
            for(i=0; i<MAX_TYPES; i=i+1) lut_idx[i] <= 0;
            
            w_en_input <= 0; w_en_display <= 0; w_start_calc <= 0;
            w_addr_ready <= 0;
        end 
        else begin
            btn_d0 <= btn[0];
            btn_d1 <= btn_d0;
            w_addr_ready <= 0; // 脉冲复位
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
                            // 2'b10: 进入计算模式
                            2'b10: current_state <= S_CALC_SELECT_OP;
                        endcase
                    end
                end

                // -----------------------------------------------------------
                // 基础模式: 存矩阵 (含 lut_valid_cnt 更新)
                // -----------------------------------------------------------
                S_INPUT_MODE, S_GEN_MODE: begin
                    w_en_input <= 1;
                    w_task_mode <= 0; // Mode 0: 完整存储
                    w_is_gen_mode <= (current_state == S_GEN_MODE);

                    if (w_dims_valid && !w_addr_ready) begin
                        w_base_addr_to_input <= calc_final_addr;
                        w_addr_ready <= 1;

                        // 更新账本逻辑
                        if (calc_match_found) begin
                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                            // [新增] 计数器饱和增加
                            if (lut_valid_cnt[calc_match_index] < 2)
                                lut_valid_cnt[calc_match_index] <= lut_valid_cnt[calc_match_index] + 1;
                        end 
                        else begin
                            if (lut_count < MAX_TYPES) begin
                                lut_m[lut_count] <= i_dim_m;
                                lut_n[lut_count] <= i_dim_n;
                                lut_start_addr[lut_count] <= free_ptr;
                                lut_idx[lut_count] <= 1;
                                lut_valid_cnt[lut_count] <= 1; // 新建，数量为1
                                
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
                // 计算流程 Step 1: 选择运算类型
                // -----------------------------------------------------------
                S_CALC_SELECT_OP: begin
                    // 假设 sw[7:5] 控制运算类型: 000=转置, 001=加法, 010=乘法
                    r_op_code <= sw[7:5]; 
                    
                    // 根据运算类型决定需要几个操作数
                    if (sw[7:5] == 3'b000) r_target_stage <= 0; // 转置只需要1个
                    else r_target_stage <= 1; // 加法需要2个 (stage 0 和 1)
                    
                    r_stage <= 0; // 从第1个操作数开始找
                    
                    // 按下确认键进入下一步
                    if (btn_confirm_pose) 
                        current_state <= S_CALC_GET_DIM;
                end

                // -----------------------------------------------------------
                // 计算流程 Step 2: 让 Input 模块只读维度
                // -----------------------------------------------------------
                S_CALC_GET_DIM: begin
                    w_en_input <= 1;
                    w_task_mode <= 1; // Mode 1: Query Dim
                    
                    // 等待 Input 模块读完 m 和 n
                    if (w_dims_valid) begin
                        w_en_input <= 0; // 暂停 Input
                        current_state <= S_CALC_FILTER;
                    end
                end

                // -----------------------------------------------------------
                // 计算流程 Step 3: 筛选逻辑 (Filter)
                // -----------------------------------------------------------
                S_CALC_FILTER: begin
                    r_match_mask <= 0;
                    
                    // 遍历账本，找符合 m, n 的矩阵
                    for (i=0; i<MAX_TYPES; i=i+1) begin
                        if (i < lut_count && lut_m[i] == i_dim_m && lut_n[i] == i_dim_n) begin
                            // 检查有几个实例
                            // ID 映射公式: ID = i*2 + instance_idx + 1
                            // Mask 位: ID - 1
                            if (lut_valid_cnt[i] >= 1) 
                                r_match_mask[i*2] <= 1;     // 第1个实例
                            if (lut_valid_cnt[i] == 2) 
                                r_match_mask[i*2 + 1] <= 1; // 第2个实例
                        end
                    end
                    // 下个周期去显示
                    // (此处可以加判断: if mask==0, 跳转报错)
                    current_state <= S_CALC_SHOW_LIST;
                end

                // -----------------------------------------------------------
                // 计算流程 Step 4: Display 显示筛选列表
                // -----------------------------------------------------------
                S_CALC_SHOW_LIST: begin
                    w_en_display <= 1;
                    w_disp_mode <= 0;   // 列表模式
                    w_disp_mask <= r_match_mask; // 告诉Display只显示这几个
                    
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        current_state <= S_CALC_GET_ID;
                    end
                end

                // -----------------------------------------------------------
                // 计算流程 Step 5: Input 读取用户选的 ID
                // -----------------------------------------------------------
                S_CALC_GET_ID: begin
                    w_en_input <= 1;
                    w_task_mode <= 2; // Mode 2: Select ID
                    
                    if (w_id_valid) begin
                        // 校验 ID 是否有效 (mask 对应位必须是1)
                        // i_input_id_val 是 1-based, 减1变 0-based
                        if (i_input_id_val > 0 && i_input_id_val <= 8 && 
                            r_match_mask[i_input_id_val-1] == 1) begin
                            
                            // ID 有效，解析出物理地址
                            // type_idx = (ID-1) / 2
                            // inst_idx = (ID-1) % 2
                            // addr = base + inst * size
                            // 注意: 这里的 size 需要重算或锁存，这里简化直接用 single_mat_size
                            // (假设 Input 刚才算的 m*n 还没变)
                            
                            // 临时变量计算 (实际需优化为 case 或寄存器)
                            // 这里简化逻辑:
                            w_disp_target_addr <= lut_start_addr[(i_input_id_val-1)>>1] + 
                                                (((i_input_id_val-1)%2) * single_mat_size);
                            
                            w_disp_m <= i_dim_m; // 记录下来给 Display 用
                            w_disp_n <= i_dim_n;
                            
                            // 记录操作数
                            if (r_stage == 0) begin
                                w_op1_addr <= lut_start_addr[(i_input_id_val-1)>>1] + 
                                            (((i_input_id_val-1)%2) * single_mat_size);
                                r_op1_m <= i_dim_m;
                                r_op1_n <= i_dim_n;
                            end else begin
                                w_op2_addr <= lut_start_addr[(i_input_id_val-1)>>1] + 
                                            (((i_input_id_val-1)%2) * single_mat_size);
                                // 此处可加维度检查 (例如加法必须 m1==m2)
                            end

                            w_en_input <= 0;
                            current_state <= S_CALC_SHOW_MAT;
                        end
                        else begin
                            // ID 无效，报错
                            current_state <= S_ERROR;
                        end
                    end
                end

                // -----------------------------------------------------------
                // 计算流程 Step 6: 回显确认 + 循环判断
                // -----------------------------------------------------------
                S_CALC_SHOW_MAT: begin
                    w_en_display <= 1;
                    w_disp_mode <= 1; // 单矩阵内容模式
                    // w_disp_target_addr 已经在上一步设置好了
                    
                    if (w_disp_done) begin
                        w_en_display <= 0;
                        
                        // 判断是否还需要找下一个操作数
                        if (r_stage < r_target_stage) begin
                            r_stage <= r_stage + 1;
                            current_state <= S_CALC_GET_DIM; // 回去重新选维度
                        end
                        else begin
                            current_state <= S_CALC_EXECUTE; // 找齐了，去计算
                        end
                    end
                end

                // -----------------------------------------------------------
                // 计算流程 Step 7: 触发计算核心
                // -----------------------------------------------------------
                S_CALC_EXECUTE: begin
                    w_start_calc <= 1; // 脉冲触发
                    w_op_code <= r_op_code;
                    // 分配结果地址 (简单起见，给 free_ptr，或者覆盖旧的)
                    w_res_addr <= free_ptr; 
                    
                    if (w_calc_done) begin
                        w_start_calc <= 0;
                        current_state <= S_IDLE; // 完成，回首页
                    end
                end

                S_ERROR: begin
                    led <= 8'b1111_1111;
                    if (btn_confirm_pose) current_state <= S_IDLE;
                end
            endcase
        end
    end
    
    // 调试输出
    always @(*) w_state = current_state;

endmodule