module Seg7_Driver (
    input wire clk,
    input wire rst_n,

    // --- 控制接口 ---
    input wire i_en,             // 显示使能 (高电平亮)
    input wire i_disp_mode,      // 显示模式: 0=运算符号(T/A/B/C), 1=数字(0-9)
    
    // 模式 0 输入: 运算代码
    input wire [2:0] i_op_code,  // 000=T, 001=A, 010=C, 011=B
    
    // 模式 1 输入: 数字数值
    input wire [3:0] i_digit_val,// 0~9
    
    // --- 物理接口 ---
    output reg [7:0] o_seg,      // 段选 (CA: 0亮1灭, 含小数点)
    output reg [3:0] o_an        // 位选 (假设4位共阳极, 0有效)
);

    // =========================================================================
    // 1. 参数定义 (共阳极 0亮1灭 .gfedcba)
    // =========================================================================
    localparam SEG_OFF = 8'hFF; // 全灭

    // 字符编码
    localparam SEG_T = 8'h87; // t
    localparam SEG_A = 8'h88; // A
    localparam SEG_B = 8'h83; // b
    localparam SEG_C = 8'hC6; // C

    // 数字编码 (0-9)
    // 0: c0, 1: f9, 2: a4, 3: b0, 4: 99, 5: 92, 6: 82, 7: f8, 8: 80, 9: 90
    reg [7:0] seg_num_lut [0:9];
    
    initial begin
        seg_num_lut[0] = 8'hc0; seg_num_lut[1] = 8'hf9; seg_num_lut[2] = 8'ha4;
        seg_num_lut[3] = 8'hb0; seg_num_lut[4] = 8'h99; seg_num_lut[5] = 8'h92;
        seg_num_lut[6] = 8'h82; seg_num_lut[7] = 8'hf8; seg_num_lut[8] = 8'h80;
        seg_num_lut[9] = 8'h90;
    end

    // =========================================================================
    // 2. 扫描时钟生成 (100MHz -> ~1kHz)
    // =========================================================================
    reg [16:0] scan_cnt; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scan_cnt <= 0;
        else scan_cnt <= scan_cnt + 1;
    end

    // =========================================================================
    // 3. 译码逻辑 (核心修改)
    // =========================================================================
    reg [7:0] decode_out;

    always @(*) begin
        if (i_disp_mode == 0) begin
            // --- 模式 0: 符号显示 ---
            case (i_op_code)
                3'b000: decode_out = SEG_T;
                3'b001: decode_out = SEG_A;
                3'b010: decode_out = SEG_C; // 矩阵乘法
                3'b011: decode_out = SEG_B; // 标量乘法
                default: decode_out = SEG_OFF;
            endcase
        end 
        else begin
            // --- 模式 1: 数字显示 ---
            if (i_digit_val <= 9) 
                decode_out = seg_num_lut[i_digit_val];
            else 
                decode_out = SEG_OFF; // 超过9不显示(或显示E)
        end
    end

    // =========================================================================
    // 4. 动态扫描输出
    // =========================================================================
    reg [1:0] digit_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) digit_sel <= 0;
        else if (scan_cnt == 0) digit_sel <= digit_sel + 1; 
    end

    always @(*) begin
        if (!i_en) begin
            o_an = 4'b1111;  // 全灭
            o_seg = SEG_OFF;
        end
        else begin
            // 这里我们让数字/字符显示在最右一位，其他位熄灭
            // (如果您想让倒计时显示在不同的位置，可以在这里修改 digit_sel 的 case)
            case (digit_sel) 
                2'b00: begin o_an = 4'b1110; o_seg = decode_out; end // Digit 0 (最右)
                2'b01: begin o_an = 4'b1101; o_seg = SEG_OFF;    end // Digit 1
                2'b10: begin o_an = 4'b1011; o_seg = SEG_OFF;    end // Digit 2
                2'b11: begin o_an = 4'b0111; o_seg = SEG_OFF;    end // Digit 3 (最左)
                default: begin o_an = 4'b1111; o_seg = SEG_OFF;  end
            endcase
        end
    end

endmodule