module FSM_Controller (
    input wire clk,
    input wire rst_n,

    //1. 物理接口 
    input wire [7:0] sw,      // sw[1:0] 模式选择
    input wire [4:0] btn,     // btn[0] 确认键
    output reg [7:0] led,     // 状态/报错指示

    //2. Input Subsystem 交互接口
    // 来自 Input 的请求
    input wire w_dims_valid,  // Input: "我有数据要存，请求分配地址"
    input wire [31:0] i_dim_m,// Input: 矩阵行数
    input wire [31:0] i_dim_n,// Input: 矩阵列数
    input wire w_rx_done,     // Input: "我存完了"
    input wire w_error_flag,  // Input: "出错了"
    // 给 Input 的指令
    output reg w_en_input,    // 启用 Input 模块
    output reg w_is_gen_mode, // 0=手动输入, 1=自动生成
    output reg w_addr_ready,  // FSM: "地址分配好了，给你"
    output reg [7:0] w_base_addr_to_input // 分配好的基地址

    // 3. 其他模块接口 (预留)
    // 比如 Calculator, Display 等...
);

    // 参数定义
    localparam S_IDLE        = 4'd0;
    localparam S_INPUT_MODE  = 4'd1; // 对应手动输入模式
    localparam S_GEN_MODE    = 4'd2; // 对应自动生成模式
    localparam S_CALC_MODE   = 4'd3; // (预留)
    localparam S_DISP_MODE   = 4'd4; // (预留)
    localparam S_ERROR       = 4'd15;

    // 假设最大支持存储 4 种不同规格的矩阵 (为了简化逻辑，防止LUT过大)
    localparam MAX_TYPES = 4;
    // 内部寄存器
    reg [3:0] current_state, next_state;
    // 内存管理单元 (MMU) 寄存器 
    // 账本：记录已存在的矩阵规格
    reg [31:0] lut_m [0:MAX_TYPES-1];     
    reg [31:0] lut_n [0:MAX_TYPES-1];    
    // 记录每种规格在 Storage 中的【起始基地址】
    reg [7:0]  lut_start_addr [0:MAX_TYPES-1];    
    // 记录每种规格当前存到第几个了 (0 或 1，实现 Round-Robin 覆盖)
    reg        lut_idx [0:MAX_TYPES-1]; 
    // 当前账本里有效记录的条数
    reg [2:0]  lut_count;
    // 指向 Storage 中下一个未使用的空闲地址
    reg [7:0]  free_ptr;

    // --- 按键消抖 (简化版) ---
    reg btn_d0, btn_d1;
    wire btn_confirm_pose;
    assign btn_confirm_pose = btn_d0 & ~btn_d1;

    // 1. 组合逻辑：MMU 查表与地址计算
    reg       calc_match_found; // 是否在账本里找到了同规格的？
    reg [2:0] calc_match_index; // 找到了的话，是第几号记录？
    reg [7:0] calc_final_addr;  // 最终决定分配给 Input 的地址
    
    // 临时变量
    integer i;
    reg [7:0] single_mat_size;  // 单个矩阵大小 (2 + m*n)
    
    always @(*) begin
        // 默认值
        calc_match_found = 0;
        calc_match_index = 0;
        calc_final_addr  = 0;
        single_mat_size  = 0;
        // 仅当 Input 发来有效请求时才进行计算
        if (w_dims_valid) begin
            // 计算单个矩阵所需空间: 头信息(2) + 数据(m*n)
            single_mat_size = 2 + (i_dim_m * i_dim_n);
            // 遍历账本 
            for (i = 0; i < MAX_TYPES; i = i + 1) begin
                // 只查有效的记录
                if (i < lut_count) begin
                    if (lut_m[i] == i_dim_m && lut_n[i] == i_dim_n) begin
                        calc_match_found = 1;
                        calc_match_index = i[2:0];
                    end
                end
            end
            // 给什么地址？
            if (calc_match_found) begin
                // 命中
                // 使用旧地盘
                // 如果 lut_idx 是 0，给基地址
                // 如果 lut_idx 是 1，给基地址 + 偏移量(单个矩阵大小)
                if (lut_idx[calc_match_index] == 0)
                    calc_final_addr = lut_start_addr[calc_match_index];
                else
                    calc_final_addr = lut_start_addr[calc_match_index] + single_mat_size;
            end 
            else begin
                // --- 未命中 (MISS) ---
                // 开辟新地盘。直接给当前的 free_ptr
                calc_final_addr = free_ptr;
            end
        end
    end

    // 2. 时序逻辑：状态机与寄存器更新 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            btn_d0 <= 0; btn_d1 <= 0;
            w_en_input <= 0; w_is_gen_mode <= 0; w_addr_ready <= 0;
            w_base_addr_to_input <= 0;
            led <= 0;
            
            // MMU 初始化
            lut_count <= 0;
            free_ptr  <= 0;
            // (lut 数组可以不用复位，靠 lut_count 控制有效性即可)
        end 
        else begin
            // 按键采样
            btn_d0 <= btn[0];
            btn_d1 <= btn_d0;
            
            // 默认信号复位 (脉冲信号)
            w_addr_ready <= 0; 
            
            // 状态机主逻辑
            case (current_state)
                S_IDLE: begin
                    w_en_input <= 0;
                    led <= 8'b0000_0001; // IDLE 指示灯
                    
                    if (btn_confirm_pose) begin
                        // 根据拨码开关跳转
                        case (sw[1:0])
                            2'b00: current_state <= S_INPUT_MODE;
                            2'b01: current_state <= S_GEN_MODE;
                            // ... 其他模式
                        endcase
                    end
                end

                S_INPUT_MODE, S_GEN_MODE: begin
                    // 1. 设置给 Input 模块的控制信号
                    w_en_input <= 1;
                    w_is_gen_mode <= (current_state == S_GEN_MODE);
                    
                    // 2. 处理地址请求握手
                    if (w_dims_valid && !w_addr_ready) begin
                        // 直接使用 "组合逻辑" 算好的结果calc_final_addr
                        w_base_addr_to_input <= calc_final_addr; // 输出地址
                        w_addr_ready <= 1; // 握手成功
                        // 3. 更新 MMU 账本
                        if (calc_match_found) begin
                            // 命中：只更新 idx，翻转它 (0->1, 1->0)
                            lut_idx[calc_match_index] <= ~lut_idx[calc_match_index];
                        end 
                        else begin
                            // 未命中：登记新规格
                            // (前提是没满，为了简单先不写满的处理)
                            if (lut_count < MAX_TYPES) begin
                                lut_m[lut_count] <= i_dim_m;
                                lut_n[lut_count] <= i_dim_n;
                                lut_start_addr[lut_count] <= free_ptr;
                                lut_idx[lut_count] <= 1; // 这次用了0号(free_ptr)，下次来该用1号了
                                
                                // 更新 free_ptr (预留两个矩阵的空间)
                                // new_free = old_free + 2 * size
                                free_ptr <= free_ptr + (single_mat_size << 1); 
                                
                                lut_count <= lut_count + 1;
                            end
                        end
                    end
                    
                    // 4. 处理完成或错误
                    if (w_rx_done) begin
                        current_state <= S_IDLE;
                        w_en_input <= 0;
                    end
                    else if (w_error_flag) begin
                        current_state <= S_ERROR;
                        w_en_input <= 0;
                    end
                end

                S_ERROR: begin
                    led <= 8'b1111_1111; // 报错全亮
                    // 等待复位或按键确认返回
                    if (btn_confirm_pose) current_state <= S_IDLE;
                end

                default: current_state <= S_IDLE;
            endcase
        end
    end
    
endmodule