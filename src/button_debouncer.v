`timescale 1ns / 1ps
module button_debouncer #(
    parameter CNT_MAX = 19'd499_999,
    parameter CNT_WIDTH = 19
) (
    input wire clk, // System clock 25MHz
    input wire rst_n,
    input wire key_in,
    output reg key_flag
    );
    reg [CNT_WIDTH-1:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt  <= 19'b0;
        else if (key_in == 1'b0)
            cnt <= 19'b0;
        else if (cnt == CNT_MAX && key_in == 1'b1)
            cnt <= cnt;
        else
            cnt <= cnt + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_flag <= 1'b0;
        else if (cnt == CNT_MAX - 1'b1)
            key_flag <= 1'b1;
        else
            key_flag <= 1'b0;
    end
    
endmodule
