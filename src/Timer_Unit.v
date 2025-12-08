module Timer_Unit #(
    parameter CLK_FREQ = 100_000_000 // 系统时钟频率
)(
    input wire clk,
    input wire rst_n,

    // --- 控制接口 ---
    input wire i_start_timer,          // 启动/重置倒计时 (脉冲有效)
    input wire i_en,             // 倒计时使能 (高电平保持计数，低电平暂停)
    input wire [3:0] sw, // 倒计时初始值 (例如 10秒)
    
    // --- 状态输出 ---
    output reg w_timeout,        // 倒计时结束信号 (脉冲)
    output reg [3:0] w_time_val  // 当前剩余秒数 (用于数码管显示)
);
    reg [31:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt<=0;
        end else if (i_start_timer) begin 
            cnt<=0;
        end else if (i_en && w_time_val>0) begin
            if (cnt==CLK_FREQ-1) cnt<=0;
            else cnt<=cnt+1;
        end else begin
            cnt<=cnt;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_timeout<=0;
            w_time_val<=4'd10;
        end else if (i_start_timer) begin
            w_timeout<=0;
            w_time_val<=sw;
        end else if (i_en) begin
            if (cnt==CLK_FREQ-1) begin
                if (w_time_val>=1) begin
                    if (w_time_val==4'd1) w_timeout<=1;
                    else w_timeout<=0;
                    w_time_val<=w_time_val-1;
                end else begin
                    w_time_val<=0;
                    w_timeout<=0;
                end
            end else begin
                w_timeout<=0;
                w_time_val<=w_time_val;
            end
        end else begin
            w_timeout<=0; 
            w_time_val<=w_time_val;
        end
    end
endmodule