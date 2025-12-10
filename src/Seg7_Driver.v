module Seg7_Driver (
    input wire clk,
    input wire rst_n,

    // --- 控制接口 ---
    input wire i_en,             // 显示使能 (高电平亮)
    input wire i_disp_mode,      // 显示模式: 0=运算符号(T/A/B/C), 1=数字(0-9)
    
    // 模式 0 输入: 运算代码
    input wire [2:0] i_op_code,  // 000=T, 001=A, 010=B, 011=C
    
    // 模式 1 输入: 数字数值
    input wire [3:0] i_digit_val,// 0~15
    
    // --- 物理接口 ---
    output reg [7:0] seg_data,
    output reg [3:0] seg_sel        
);
    localparam SEG_OFF = 8'h00;  //[7:0]: a, b, c, d, e, f, g, dp
    localparam SEG_T = 8'h1E;
    localparam SEG_A = 8'hEE;
    localparam SEG_B = 8'hCE;
    localparam SEG_C = 8'h9C; 
    localparam SEG_E = 8'h9E; 
    
    /*reg [7:0] SEG_NUM [0:9];
    initial begin
        SEG_NUM[0] = 8'hFC;
        SEG_NUM[1] = 8'h60;
        SEG_NUM[2] = 8'hDA;
        SEG_NUM[3] = 8'hF2;
        SEG_NUM[4] = 8'h66;
        SEG_NUM[5] = 8'hB6;
        SEG_NUM[6] = 8'hBE;
        SEG_NUM[7] = 8'hE0;
        SEG_NUM[8] = 8'hFE;
        SEG_NUM[9] = 8'hF6;
    end*/
    //localparam [7:0] SEG_NUM[0:9]={8'hFC, 8'h60, 8'hDA, 8'hF2, 8'h66, 8'hB6, 8'hBE, 8'hE0, 8'hFE, 8'hF6};
    localparam [7:0] SEG_NUM[0:9] = '{
        8'hFC, 8'h60, 8'hDA, 8'hF2, 8'h66, 
        8'hB6, 8'hBE, 8'hE0, 8'hFE, 8'hF6
    };

    reg [14:0] cnt;
    reg [1:0] scan_cnt;
    
    reg [7:0] decode_out[0:3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt<=0;
        end else begin
            cnt<=cnt+1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt<=0;
        end else begin
            if (cnt==0) scan_cnt<=scan_cnt+1;
            else scan_cnt<=scan_cnt;
        end
    end

    always @(*) begin
        if (!i_en) begin
            decode_out[0]=SEG_OFF;
            decode_out[1]=SEG_OFF;
            decode_out[2]=SEG_OFF;
            decode_out[3]=SEG_OFF;
        end else if (!i_disp_mode) begin
            decode_out[1]=SEG_OFF;
            decode_out[2]=SEG_OFF;
            decode_out[3]=SEG_OFF;
            case(i_op_code)
                3'd0: decode_out[0]=SEG_T;
                3'd1: decode_out[0]=SEG_A;
                3'd2: decode_out[0]=SEG_B;
                3'd3: decode_out[0]=SEG_C;
                default: decode_out[0]=SEG_E;
            endcase
        end else begin
            if (i_digit_val>=10) begin
                decode_out[0]=SEG_NUM[i_digit_val-10];
                decode_out[1]=SEG_NUM[1];
            end else begin
                decode_out[0]=SEG_NUM[i_digit_val];
                decode_out[1]=SEG_OFF;
            end
            decode_out[2]=SEG_OFF;
            decode_out[3]=SEG_OFF;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_sel<=0;
            seg_data<=0;
        end else if (!i_en) begin
            seg_sel<=0;
            seg_data<=0;
        end else begin
            seg_data<=decode_out[scan_cnt];
            case (scan_cnt)
                2'b00: seg_sel<=4'b0001;
                2'b01: seg_sel<=4'b0010;
                2'b10: seg_sel<=4'b0100;
                2'b11: seg_sel<=4'b1000;
                default: seg_sel<=4'b0000;
            endcase
        end
    end
endmodule