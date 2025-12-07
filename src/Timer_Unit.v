module Timer_Unit #(
    parameter CLK_FREQ = 100_000_000 // 系统时钟频率
)(
    input wire clk,
    input wire rst_n,

    // --- 控制接口 ---
    input wire i_start,          // 启动/重置倒计时 (脉冲有效)
    input wire i_en,             // 倒计时使能 (高电平保持计数，低电平暂停)
    input wire [3:0] i_init_val, // 倒计时初始值 (例如 10秒)
    
    // --- 状态输出 ---
    output reg o_timeout,        // 倒计时结束信号 (脉冲)
    output reg [3:0] o_curr_sec  // 当前剩余秒数 (用于数码管显示)
);

    // =========================================================================
    // 1. 1秒分频计数器
    // =========================================================================
    localparam CNT_1S_MAX = CLK_FREQ - 1;
    reg [31:0] cnt_1s;
    wire tick_1s;

    // 产生 1秒 的脉冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1s <= 0;
        end 
        else if (i_start) begin
            cnt_1s <= 0; // 重新启动时清零分频器
        end
        else if (i_en && o_curr_sec > 0) begin
            if (cnt_1s == CNT_1S_MAX) cnt_1s <= 0;
            else cnt_1s <= cnt_1s + 1;
        end
    end

    assign tick_1s = (cnt_1s == CNT_1S_MAX);

    // =========================================================================
    // 2. 秒倒计数逻辑
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_curr_sec <= 4'd10; // 默认值
            o_timeout <= 0;
        end 
        else if (i_start) begin
            o_curr_sec <= i_init_val; // 加载初始值 (比如 10)
            o_timeout <= 0;
        end
        else if (i_en) begin
            o_timeout <= 0; // 默认拉低
            if (tick_1s) begin
                if (o_curr_sec > 0) begin
                    o_curr_sec <= o_curr_sec - 1;
                    // 如果减完是0，则触发超时
                    if (o_curr_sec == 1) o_timeout <= 1; 
                end
            end
        end
    end

endmodule