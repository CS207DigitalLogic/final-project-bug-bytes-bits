module Timer_Unit (
    input wire clk,
    input wire rst_n,

    // 控制接口
    input wire w_start_timer,   // FSM: "开始倒计时！" (脉冲)
    
    // 配置接口 (来自 Top -> 外部开关)
    // 根据文档，用户可以通过开关配置时间 (5-15s)
    input wire [7:0] sw,        

    // 输出接口
    output reg w_timeout,       // 告诉 FSM: "时间到了！" (脉冲)
    output reg [3:0] w_time_val // 当前剩余秒数 (给数码管显示)
);

    // 参数定义
    parameter CLK_FREQ = 100_000_000; // 100MHz 系统时钟
    
    // 内部寄存器
    reg [31:0] cnt_1s;  // 用于产生 1秒 脉冲的计数器
    wire tick_1s;       // 1秒 脉冲信号

    // ============================================================
    // 1. 秒脉冲产生逻辑 (分频器)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1s <= 0;
        end else begin
            if (w_start_timer) begin
                cnt_1s <= 0; // 每次重新启动时，把秒表归零，保证第一秒是完整的
            end 
            else if (cnt_1s >= CLK_FREQ - 1) begin
                cnt_1s <= 0; // 计满 1秒，归零
            end 
            else begin
                cnt_1s <= cnt_1s + 1;
            end
        end
    end

    // 当计数器数到最大值时，产生一个周期的 tick 信号
    assign tick_1s = (cnt_1s == CLK_FREQ - 1);

    // ============================================================
    // 2. 倒计时主逻辑
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_time_val <= 4'd10;
            w_timeout <= 0;
        end else begin
            // 默认拉低超时信号 (脉冲)
            w_timeout <= 0;

            if (w_start_timer) begin
                // --- 加载初始值 (动态配置逻辑) ---
                // 检查开关 sw[3:0] 是否在 5-15 之间
                if (sw[3:0] >= 4'd5 && sw[3:0] <= 4'd15) begin
                    w_time_val <= sw[3:0]; // 合法，使用开关设定的时间
                end else begin
                    w_time_val <= 4'd10;   // 不合法，使用默认 10秒
                end
            end
            else if (w_time_val > 0) begin
                // 如果还没数到 0，且过了一秒 (tick_1s)，就减 1
                if (tick_1s) begin
                    w_time_val <= w_time_val - 1;
                    
                    // 如果减完变成了 0，说明超时了
                    if (w_time_val - 1 == 0) begin
                        w_timeout <= 1; // 触发超时信号
                    end
                end
            end
        end
    end

endmodule