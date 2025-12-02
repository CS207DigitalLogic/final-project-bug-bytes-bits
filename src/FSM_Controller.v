module FSM_Controller (
    input wire clk,
    input wire rst_n,

    // 1. 外部控制输入 (来自 Top -> 物理引脚)
    input wire [7:0] sw,      // 开关: 用于选择模式、设置参数
    input wire [4:0] btn,     // 按钮: btn[0]为确认键

    // 2. 子模块反馈信号 (Internal Flags)
    input wire w_rx_done,     // Input模块: 输入完成
    input wire w_error_flag,  // Input模块: 输入非法
    input wire w_gen_done,    // Gen模块: 生成完成 (预留)
    input wire w_disp_done,   // Display模块: 显示完成
    input wire w_calc_done,   // Calc模块: 计算完成
    input wire w_timeout,     // Timer模块: 倒计时结束

    // 3. 输出给 Top 的多路选择控制 (Mux Select)
    output reg [3:0] w_state, // 当前状态码，用于控制 Storage MUX 和 Display MUX

    // 4. 输出给子模块的控制信号 (Enables / Starts)
    output reg w_en_input,    // 启动 Input Subsystem
    output reg w_start_calc,  // 启动 Calculator
    output reg w_start_disp,  // 启动 Display
    output reg w_start_timer, // 启动 Timer 倒计时
    output reg [2:0] w_op_code, // 告诉 Calc 做什么运算
    
    // 5. 物理输出
    output reg [7:0] led      // 报错灯
);

    // --- 状态编码 (State Encoding) ---
    localparam S_IDLE        = 4'd0; // 主菜单
    localparam S_INPUT       = 4'd1; // 模式1: 输入
    localparam S_GEN         = 4'd2; // 模式2: 生成
    localparam S_DISPLAY     = 4'd3; // 模式3: 显示
    localparam S_OP_SELECT   = 4'd4; // 模式4: 选运算类型
    localparam S_OPERAND_SEL = 4'd5; // 模式4: 选操作数(简化版，暂不细分A/B)
    localparam S_ERROR_WAIT  = 4'd6; // 错误报错
    localparam S_CALCULATE   = 4'd7; // 执行计算
    localparam S_RESULT_OUT  = 4'd8; // 输出结果
    localparam S_OP_DONE     = 4'd9; // 等待用户决定(继续/退出)

    reg [3:0] current_state, next_state;

    // --- 辅助逻辑: 按键边沿检测 ---
    // 我们需要检测 btn[0] (确认键) 的上升沿
    reg btn_confirm_d0, btn_confirm_d1;
    wire btn_confirm_posedge;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            btn_confirm_d0 <= 0;
            btn_confirm_d1 <= 0;
        end else begin
            btn_confirm_d0 <= btn[0];
            btn_confirm_d1 <= btn_confirm_d0;
        end
    end
    assign btn_confirm_posedge = (btn_confirm_d0 && !btn_confirm_d1);

    // --- 辅助寄存器 ---
    // 用于存储用户选择的运算类型 (从开关读取)
    reg [2:0] reg_op_code; 

    // ============================================================
    // 1. 状态跳转逻辑 (Sequential Logic)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            current_state <= S_IDLE;
        else 
            current_state <= next_state;
    end

    // ============================================================
    // 2. 下一状态判断逻辑 (Combinational Logic)
    // ============================================================
    always @(*) begin
        // 默认保持当前状态
        next_state = current_state;

        case (current_state)
            // ----------------------------------------------------
            // 状态 0: 主菜单 (IDLE)
            // ----------------------------------------------------
            S_IDLE: begin
                // 等待按下确认键
                if (btn_confirm_posedge) begin
                    // 根据开关 sw[1:0] 决定去哪个模式
                    case (sw[1:0])
                        2'b00: next_state = S_INPUT;     // 模式1
                        2'b01: next_state = S_GEN;       // 模式2 (暂未实现)
                        2'b10: next_state = S_DISPLAY;   // 模式3
                        2'b11: next_state = S_OP_SELECT; // 模式4
                    endcase
                end
            end

            // ----------------------------------------------------
            // 状态 1: 矩阵输入 (INPUT)
            // ----------------------------------------------------
            S_INPUT: begin
                if (w_rx_done)          next_state = S_IDLE;       // 成功收完，回菜单
                else if (w_error_flag)  next_state = S_ERROR_WAIT; // 发现非法字符，去报错
            end

            // ----------------------------------------------------
            // 状态 2: 矩阵生成 (GEN) - 预留
            // ----------------------------------------------------
            S_GEN: begin
                if (w_gen_done) next_state = S_IDLE;
            end

            // ----------------------------------------------------
            // 状态 3: 矩阵显示 (DISPLAY)
            // ----------------------------------------------------
            S_DISPLAY: begin
                if (w_disp_done) next_state = S_IDLE;
            end

            // ----------------------------------------------------
            // 状态 4: 运算选择 (OP_SELECT)
            // ----------------------------------------------------
            S_OP_SELECT: begin
                // 在这个状态，数码管会显示开关选中的 'A', 'C' 等字符
                // 等待用户设置好开关并按确认
                if (btn_confirm_posedge) begin
                    next_state = S_OPERAND_SEL;
                end
            end

            // ----------------------------------------------------
            // 状态 5: 操作数选择 (OPERAND_SEL)
            // ----------------------------------------------------
            S_OPERAND_SEL: begin
                // 这里应该有复杂的检查逻辑 (如维度匹配)
                // 简化版：默认检查通过，或者如果你有 w_operand_valid 信号可加在这里
                // 假设直接通过：
                next_state = S_CALCULATE;
                
                // 如果需要检查，逻辑如下：
                // if (valid) next_state = S_CALCULATE;
                // else next_state = S_ERROR_WAIT;
            end

            // ----------------------------------------------------
            // 状态 6: 错误等待 (ERROR_WAIT)
            // ----------------------------------------------------
            S_ERROR_WAIT: begin
                // 两种出路：
                // 1. 倒计时结束 -> 强行回菜单
                if (w_timeout) begin
                    next_state = S_IDLE;
                end
                // 2. 用户如果在这个状态下又有操作(比如重新输入)，可以跳回 Input
                // 这里简化处理：必须等倒计时结束
            end

            // ----------------------------------------------------
            // 状态 7: 执行计算 (CALCULATE)
            // ----------------------------------------------------
            S_CALCULATE: begin
                if (w_calc_done) next_state = S_RESULT_OUT;
            end

            // ----------------------------------------------------
            // 状态 8: 结果输出 (RESULT_OUT)
            // ----------------------------------------------------
            S_RESULT_OUT: begin
                // 借用 Display 模块把结果发给串口
                if (w_disp_done) next_state = S_OP_DONE;
            end

            // ----------------------------------------------------
            // 状态 9: 完成等待 (OP_DONE)
            // ----------------------------------------------------
            S_OP_DONE: begin
                if (btn_confirm_posedge) begin
                    // 根据开关决定：继续算 还是 回菜单？
                    // 假设 sw[7] = 1 表示继续，0 表示退出
                    if (sw[7]) next_state = S_OP_SELECT;
                    else       next_state = S_IDLE;
                end
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // ============================================================
    // 3. 输出逻辑 (Output Logic)
    // ============================================================
    
    // 输出状态码给 Top (用于控制 MUX)
    always @(*) begin
        w_state = current_state;
    end

    // 控制各个子模块的 Enable / Start 信号
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            w_en_input    <= 0;
            w_start_calc  <= 0;
            w_start_disp  <= 0;
            w_start_timer <= 0;
            led           <= 0;
            w_op_code     <= 0;
            reg_op_code   <= 0;
        end else begin
            // --- 默认全部拉低 (脉冲复位) ---
            w_start_calc  <= 0;
            w_start_disp  <= 0;
            w_start_timer <= 0;
            // w_en_input 需要维持高电平，不能做成脉冲，单独处理
            
            case (next_state) // 使用 next_state 以便在进入状态的第一拍就生效
                
                S_INPUT: begin
                    w_en_input <= 1; // 持续使能
                end
                
                S_ERROR_WAIT: begin
                    w_en_input <= 0; // 停止输入
                    led <= 8'hFF;    // 全亮报错
                    if (current_state != S_ERROR_WAIT) begin
                        w_start_timer <= 1; // 刚进入的一瞬间，启动倒计时
                    end
                end
                
                S_OP_SELECT: begin
                    // 锁存用户选择的运算类型 (假设 sw[6:4] 是类型)
                    reg_op_code <= sw[6:4]; 
                    w_op_code <= sw[6:4]; // 实时更新给数码管看
                end

                S_CALCULATE: begin
                    w_op_code <= reg_op_code; // 把锁存的操作码给计算器
                    if (current_state != S_CALCULATE)
                        w_start_calc <= 1; // 刚进入时给一个 Start 脉冲
                end

                S_DISPLAY: begin
                    if (current_state != S_DISPLAY)
                        w_start_disp <= 1; // 刚进入时给一个 Start 脉冲
                end
                
                S_RESULT_OUT: begin
                    // 复用显示模块
                    if (current_state != S_RESULT_OUT)
                        w_start_disp <= 1; 
                end

                default: begin
                    w_en_input <= 0;
                    led <= 0; // 关灯
                end
            endcase
        end
    end

endmodule