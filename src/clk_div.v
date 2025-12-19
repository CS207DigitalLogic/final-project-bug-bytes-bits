`timescale 1ns / 1ps

module clk_div(
    input wire clk, 
    input wire rst_n, 
    output reg clk_out
);
    parameter period = 4;
    reg [3:0] cnt;

    initial begin
        cnt = 0;
        clk_out = 0;
    end

    always @(posedge clk) begin
        if (cnt == ((period >> 1) - 1)) begin
            clk_out <= ~clk_out;
            cnt <= 0;
        end else begin
            cnt <= cnt + 1;
        end
    end

endmodule