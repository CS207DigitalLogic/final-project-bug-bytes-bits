module Input_Subsystem (
    input wire clk,
    input wire rst_n,
    
    // 1. 物理接口 (Top 会把 UART_RX 引脚连到这里)
    input wire uart_rx_pin,

    // 2. 控制接口 (FSM 会发指令)
    input wire w_en_input,    // FSM: "开始监听输入！"

    // 3. 存储接口 (输出给 Storage MUX)
    output reg w_input_we,          // 写使能
    output reg [7:0] w_input_addr,  // 写地址
    output reg [31:0] w_input_data, // 写数据
    
    // 4. 反馈标志
    output reg w_rx_done,     // (预留)
    output reg w_error_flag   // 告诉 FSM: "刚才输入的不是数字！"
);

    // --- 内部信号 ---
    wire [7:0] rx_byte;       // 存 uart_rx 解析出来的 8位 ASCII
    wire rx_pulse;            // 存 uart_rx 的完成脉冲
    reg [31:0] temp_val;      // 累加当前输入的数字 (比如输入 "12", 先存1, 再变成12)

    // ============================================================
    // 1. 例化你的 uart_rx 模块 (根据你上传的文件)
    // ============================================================
    uart_rx #(
        .CLK_FREQ(100_000_000), // 确保和你板子晶振一致
        .BAUD_RATE(115200)      // 确保和串口助手一致
    ) u_uart_driver (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_pin),     // 连接外部引脚
        .rx_data(rx_byte),    // [重要] 对应你文件的端口名
        .rx_done(rx_pulse)    // [重要] 对应你文件的端口名
    );

    // ============================================================
    // 2. 解析逻辑 (ASCII -> 整数)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_input_we <= 0;
            w_input_addr <= 0;
            w_input_data <= 0;
            w_error_flag <= 0;
            temp_val <= 0;
            w_rx_done <= 0;
        end 
        else if (w_en_input) begin 
            w_input_we <= 0; // 默认拉低写使能 (脉冲信号)
            w_error_flag <= 0; // 错误标志是脉冲或持续均可，这里做脉冲复位

            // 当底层驱动说 "收到一个字节" 时
            if (rx_pulse) begin
                
                // --- 情况 A: 收到数字 '0'(0x30) ~ '9'(0x39) ---
                if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                    // 算法: 新值 = 旧值 * 10 + (新数字)
                    // 比如之前是 1，现在来了 '2'，变成 1*10 + 2 = 12
                    temp_val <= temp_val * 10 + (rx_byte - 8'h30);
                end
                
                // --- 情况 B: 收到分隔符 (空格 0x20, 回车 0x0D, 换行 0x0A) ---
                // 这意味着一个完整的数字输完了，该存进仓库了
                else if (rx_byte == 8'h20 || rx_byte == 8'h0D || rx_byte == 8'h0A) begin
                    w_input_data <= temp_val;      // 把累加好的数放上去
                    w_input_we <= 1;               // 告诉仓库: "存！"
                    w_input_addr <= w_input_addr + 1; // 地址移到下一格
                    temp_val <= 0;                 // 清零，准备接下一个数
                end
                
                // --- 情况 C: 收到非法字符 (比如 'a', '!') ---
                else begin
                    w_error_flag <= 1; // 报错！让 FSM 去处理倒计时
                end
            end
        end
        else begin
            // 当 FSM 不使能时 (比如进入了计算模式)，清空临时状态
            temp_val <= 0;
            w_error_flag <= 0;
            // 注意：不要清空 w_input_addr，因为可能分几次输入
        end
    end

endmodule