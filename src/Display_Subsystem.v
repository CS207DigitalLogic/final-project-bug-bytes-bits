module Display_Subsystem (
    input wire clk,
    input wire rst_n,

    // 1. 物理接口 (输出到 Top -> 外部引脚)
    output wire uart_tx_pin,

    // 2. 控制接口 (来自 FSM)
    input wire w_start_disp,  // FSM 说：“开始显示！”
    output reg w_disp_done,   // 告诉 FSM：“所有矩阵都显示完了”
    output wire w_tx_busy,    // (可选) 告诉 FSM 正在忙

    // 3. 存储接口 (输入来自 Storage MUX)
    output reg [7:0] w_disp_addr,   // 读地址
    input wire [31:0] w_storage_out // 读到的数据
);

    // --- 内部状态定义 ---
    localparam S_IDLE       = 0;
    localparam S_READ_MEM   = 1;
    localparam S_SEND_DIGIT = 2;
    localparam S_WAIT_TX    = 3;
    localparam S_SEND_SPACE = 4;
    localparam S_WAIT_SPACE = 5;
    localparam S_CHECK_NEXT = 6;
    localparam S_SEND_ENTER = 7; // 发送换行
    localparam S_WAIT_ENTER = 8;
    localparam S_DONE       = 9;

    reg [3:0] state;
    reg [31:0] data_reg; // 暂存从仓库读出来的数

    // UART 驱动接口信号
    reg tx_trigger;      // 触发发送信号
    reg [7:0] tx_byte;   // 要发的字符
    wire tx_driver_busy; // 驱动忙标志

    // 辅助计数器
    reg [7:0] count;     // 记录已经显示了多少个数
    // 假设我们要显示 矩阵A(25个) + 矩阵B(25个) + 维度信息，简单起见，先设个固定范围
    // 在实际项目中，你应该先读地址0获取维度，这里为了演示，假设显示前 10 个数
    localparam MAX_SHOW = 10; 

    assign w_tx_busy = (state != S_IDLE); // 只要不是空闲，就是忙

    // ============================================================
    // 1. 例化老师的 UART TX 模块
    // ============================================================
    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_trigger), // 我们控制它开始发
        .tx_data(tx_byte),     // 我们给它字符
        .tx(uart_tx_pin),      // 连到外部引脚
        .tx_busy(tx_driver_busy) // 它告诉我们要等待
    );

    // ============================================================
    // 2. 主状态机逻辑
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            w_disp_addr <= 0;
            w_disp_done <= 0;
            tx_trigger <= 0;
            tx_byte <= 0;
            count <= 0;
        end 
        else begin
            case (state)
                // --- 1. 等待开始 ---
                S_IDLE: begin
                    w_disp_done <= 0;
                    if (w_start_disp) begin
                        state <= S_READ_MEM;
                        w_disp_addr <= 0; // 从地址 0 开始读
                        count <= 0;
                    end
                end

                // --- 2. 读存储器 ---
                S_READ_MEM: begin
                    // 地址 w_disp_addr 已经给出，数据 w_storage_out 会在下一个周期准备好
                    // 为了稳妥，这里可以加一个周期的延时，或者直接跳去发数据
                    state <= S_SEND_DIGIT;
                end

                // --- 3. 发送数字 ---
                S_SEND_DIGIT: begin
                    data_reg <= w_storage_out; // 锁存读到的数据
                    
                    // [核心转换]: 整数转 ASCII
                    // 假设数据是 0-9。如果是 5，就发 '5' (0x35)
                    tx_byte <= w_storage_out[7:0] + 8'h30; 
                    
                    tx_trigger <= 1; // 触发发送！
                    state <= S_WAIT_TX;
                end

                // --- 4. 等待发送完成 ---
                S_WAIT_TX: begin
                    tx_trigger <= 0; // 撤销触发信号
                    // 必须等驱动先变忙(busy=1)，再变空闲(busy=0)才算完
                    // 这里简化逻辑：只要 busy 为 0 且 trigger 已经撤销，说明发完了
                    // (实际老师的代码逻辑可能是组合逻辑 busy，这里需要小心时序，最稳妥是等一拍)
                    if (!tx_driver_busy) begin
                        state <= S_SEND_SPACE;
                    end
                end

                // --- 5. 发送空格 (分隔符) ---
                S_SEND_SPACE: begin
                    tx_byte <= 8'h20; // 空格的 ASCII
                    tx_trigger <= 1;
                    state <= S_WAIT_SPACE;
                end

                S_WAIT_SPACE: begin
                    tx_trigger <= 0;
                    if (!tx_driver_busy) state <= S_CHECK_NEXT;
                end

                // --- 6. 检查是否全部发完 ---
                S_CHECK_NEXT: begin
                    // 准备读下一个地址
                    w_disp_addr <= w_disp_addr + 1;
                    count <= count + 1;

                    // 判断是否结束 (这里写死显示 10 个，实际要根据维度判断)
                    if (count >= MAX_SHOW - 1) begin
                        state <= S_SEND_ENTER; // 发个回车表示结束
                    end else begin
                        state <= S_READ_MEM;   // 回去读下一个数
                    end
                end
                
                // --- 7. 发送回车 (可选，为了美观) ---
                S_SEND_ENTER: begin
                    tx_byte <= 8'h0A; // 换行符
                    tx_trigger <= 1;
                    state <= S_WAIT_ENTER;
                end
                
                S_WAIT_ENTER: begin
                    tx_trigger <= 0;
                    if (!tx_driver_busy) state <= S_DONE;
                end

                // --- 8. 完成 ---
                S_DONE: begin
                    w_disp_done <= 1; // 告诉 FSM 完成了
                    // 等待 start 信号消失，防止重复触发
                    if (!w_start_disp) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule