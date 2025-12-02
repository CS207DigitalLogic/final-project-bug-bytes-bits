module Seg7_Driver (
    input wire clk,
    input wire rst_n,

    input wire [31:0] w_seg_data, // 要显示的数据
    input wire [1:0] w_seg_mode,  // 0=显示十进制/十六进制数, 1=显示特定字符

    output reg [7:0] seg_sel,     // 位选 (选择哪一位亮)
    output reg [7:0] seg_data     // 段选 (a-g dp)
);

    // --- 1. 分频产生扫描时钟 (1kHz 左右) ---
    // 100MHz / 100,000 = 1kHz
    reg [16:0] clk_cnt;
    wire scan_tick;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_cnt <= 0;
        else if (clk_cnt >= 100_000) clk_cnt <= 0;
        else clk_cnt <= clk_cnt + 1;
    end
    assign scan_tick = (clk_cnt == 100_000);

    // --- 2. 扫描位置计数器 (0-7) ---
    reg [2:0] scan_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scan_idx <= 0;
        else if (scan_tick) scan_idx <= scan_idx + 1;
    end

    // --- 3. 位选逻辑 (Active Low or High? EGO1 通常是低电平有效) ---
    always @(*) begin
        case (scan_idx)
            3'd0: seg_sel = 8'b11111110; // 最右边一位
            3'd1: seg_sel = 8'b11111101;
            3'd2: seg_sel = 8'b11111011;
            3'd3: seg_sel = 8'b11110111;
            3'd4: seg_sel = 8'b11101111;
            3'd5: seg_sel = 8'b11011111;
            3'd6: seg_sel = 8'b10111111;
            3'd7: seg_sel = 8'b01111111; // 最左边一位
            default: seg_sel = 8'b11111111;
        endcase
    end

    // --- 4. 数据提取逻辑 ---
    // 根据 scan_idx 决定当前这一位要显示什么 4-bit 数据
    reg [3:0] hex_digit;
    
    always @(*) begin
        if (w_seg_mode == 1) begin
            // 字符模式：固定显示在最右边或特定位置
            // 为了简单，我们只在 scan_idx == 0 (最右位) 显示字符
            if (scan_idx == 0) hex_digit = w_seg_data[3:0]; 
            else hex_digit = 4'hF; // 其他位黑屏 (F 定义为灭)
        end 
        else begin
            // 数字模式：把 32位 拆成 8个 4位 16进制数
            case (scan_idx)
                3'd0: hex_digit = w_seg_data[3:0];
                3'd1: hex_digit = w_seg_data[7:4];
                3'd2: hex_digit = w_seg_data[11:8];
                3'd3: hex_digit = w_seg_data[15:12];
                3'd4: hex_digit = w_seg_data[19:16];
                3'd5: hex_digit = w_seg_data[23:20];
                3'd6: hex_digit = w_seg_data[27:24];
                3'd7: hex_digit = w_seg_data[31:28];
            endcase
        end
    end

    // --- 5. 段选译码 (共阳极? 共阴极? EGO1 通常是共阴极-高电平亮 或 共阳极-低电平亮) ---
    // 假设：EGO1 数码管是【共阴极】(高电平亮) 或者通过驱动反相。
    // 如果上板后发现显示的字是反的（亮的变灭，灭的变亮），把下面的 bit 取反即可 (~)。
    
    // 字符定义：0=T, 1=A, 2=B, 3=C, 4=J (对应 MUX 里的定义)
    
    always @(*) begin
        if (w_seg_mode == 1) begin
            // --- 字符译码表 ---
            case (hex_digit) // 这里的 hex_digit 其实是 MUX 传来的 CHAR_ID
                4'd1: seg_data = 8'b0000_1111; // 't' (这里简化为 t 的样子: d,e,f,g)
                4'd2: seg_data = 8'b0111_0111; // 'A'
                4'd3: seg_data = 8'b0111_1100; // 'b'
                4'd4: seg_data = 8'b0011_1001; // 'C'
                4'd5: seg_data = 8'b0001_1110; // 'J'
                default: seg_data = 8'b0000_0000; // 灭
            endcase
        end 
        else begin
            // --- 数字译码表 (0-F) ---
            case (hex_digit)
                4'h0: seg_data = 8'b0011_1111; // 0
                4'h1: seg_data = 8'b0000_0110; // 1
                4'h2: seg_data = 8'b0101_1011; // 2
                4'h3: seg_data = 8'b0100_1111; // 3
                4'h4: seg_data = 8'b0110_0110; // 4
                4'h5: seg_data = 8'b0110_1101; // 5
                4'h6: seg_data = 8'b0111_1101; // 6
                4'h7: seg_data = 8'b0000_0111; // 7
                4'h8: seg_data = 8'b0111_1111; // 8
                4'h9: seg_data = 8'b0110_1111; // 9
                4'hA: seg_data = 8'b0111_0111; // A
                4'hB: seg_data = 8'b0111_1100; // b
                4'hC: seg_data = 8'b0011_1001; // C
                4'hD: seg_data = 8'b0101_1110; // d
                4'hE: seg_data = 8'b0111_1001; // E
                4'hF: seg_data = 8'b0000_0000; // F (定义为灭)
                default: seg_data = 8'b0000_0000;
            endcase
        end
    end

endmodule