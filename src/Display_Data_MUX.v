module Display_Data_MUX (
    // 1. 控制信号
    input wire [3:0] w_state,

    // 2. 数据源
    input wire [3:0] w_time_val,      // 来自 Timer (倒计时)
    input wire [31:0] w_cycle_count,  // 来自 Calculator (卷积周期)
    input wire [2:0] w_op_code,       // 来自 FSM (操作类型)

    // 3. 输出给驱动
    output reg [31:0] w_seg_data,     // 要显示的数值
    output reg [1:0] w_seg_mode       // 显示模式: 0=数字, 1=字符
);

    // 状态定义
    localparam S_OP_SELECT   = 4'd4;
    localparam S_ERROR_WAIT  = 4'd6;
    localparam S_OP_DONE     = 4'd9;

    // 运算类型定义
    localparam OP_TRANSPOSE = 3'd0; // 't'
    localparam OP_ADD       = 3'd1; // 'A'
    localparam OP_SCALAR    = 3'd2; // 'b' (Base) 或 'n'
    localparam OP_MULT      = 3'd3; // 'C'
    localparam OP_CONV      = 3'd4; // 'J' (Juan 卷积)

    // 字符编码 (自定义的假数据，驱动里会解析)
    localparam CHAR_T = 32'h00000001;
    localparam CHAR_A = 32'h00000002;
    localparam CHAR_B = 32'h00000003;
    localparam CHAR_C = 32'h00000004;
    localparam CHAR_J = 32'h00000005;

    always @(*) begin
        // 默认显示 0
        w_seg_data = 0;
        w_seg_mode = 0; // 模式0: 普通数字

        case (w_state)
            // --- 情况 1: 选运算模式 (显示字符 A, C, T...) ---
            S_OP_SELECT: begin
                w_seg_mode = 1; // 模式1: 字符模式
                case (w_op_code)
                    OP_TRANSPOSE: w_seg_data = CHAR_T;
                    OP_ADD:       w_seg_data = CHAR_A;
                    OP_SCALAR:    w_seg_data = CHAR_B;
                    OP_MULT:      w_seg_data = CHAR_C;
                    default:      w_seg_data = CHAR_J;
                endcase
            end

            // --- 情况 2: 错误倒计时 (显示 10, 9...) ---
            S_ERROR_WAIT: begin
                w_seg_mode = 0; // 数字模式
                w_seg_data = {28'd0, w_time_val}; // 补齐 32位
            end

            // --- 情况 3: 运算完成 (显示卷积周期数) ---
            S_OP_DONE: begin
                w_seg_mode = 0; // 数字模式
                // 只有卷积才显示周期，其他可能显示个 0 或者别的
                // 这里简单处理：直接显示 Calculator 给的计数值
                w_seg_data = w_cycle_count; 
            end

            default: begin
                w_seg_data = 0;
                w_seg_mode = 0;
            end
        endcase
    end

endmodule