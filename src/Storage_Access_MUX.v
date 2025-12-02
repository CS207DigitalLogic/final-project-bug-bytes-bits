module Storage_Access_MUX (
    // 1. 控制信号 (来自 FSM)
    input wire [3:0] w_state,

    // 2. 通道 A: Input Subsystem (输入模块)
    input wire [7:0] w_input_addr,
    input wire [31:0] w_input_data,
    input wire w_input_we,

    // 3. 通道 B: Calculator Core (计算模块)
    input wire [7:0] w_calc_addr,
    input wire [31:0] w_calc_data,
    input wire w_calc_we,

    // 4. 通道 C: Display Subsystem (显示模块 - 只读)
    input wire [7:0] w_disp_addr,

    // 5. 输出: 连接到 Matrix Storage
    output reg [7:0] w_storage_addr,
    output reg [31:0] w_storage_data,
    output reg w_storage_we
);

    // 状态定义 (必须与 FSM 保持一致)
    localparam S_INPUT       = 4'd1;
    localparam S_DISPLAY     = 4'd3;
    localparam S_CALCULATE   = 4'd7;
    localparam S_RESULT_OUT  = 4'd8; // 结果输出时也是 Display 模块在读

    always @(*) begin
        case (w_state)
            // --- 模式 1: 输入模块独占 ---
            S_INPUT: begin
                w_storage_addr = w_input_addr;
                w_storage_data = w_input_data;
                w_storage_we   = w_input_we;
            end

            // --- 模式 4: 计算模块独占 ---
            S_CALCULATE: begin
                w_storage_addr = w_calc_addr;
                w_storage_data = w_calc_data;
                w_storage_we   = w_calc_we;
            end

            // --- 模式 3/4: 显示模块独占 (只读) ---
            S_DISPLAY, S_RESULT_OUT: begin
                w_storage_addr = w_disp_addr;
                w_storage_data = 32'd0; // 读操作不关心写入数据
                w_storage_we   = 1'b0;  // 强制禁止写入
            end

            // --- 其他状态: 默认安全模式 ---
            default: begin
                w_storage_addr = 8'd0;
                w_storage_data = 32'd0;
                w_storage_we   = 1'b0;
            end
        endcase
    end

endmodule