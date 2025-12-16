module Matrix_storage (
    input clk,
    input w_storage_we,
    input [31:0] w_storage_data,
    input [7:0] w_storage_addr,
    output [31:0] w_storage_out
);

reg [31:0] mem [0:511];
always @(posedge clk) begin
    if (w_storage_we) begin
        mem[w_storage_addr] <= w_storage_data;//位宽隐式对齐
    end
end

assign w_storage_out = mem[w_storage_addr];//异步读取数据
    
endmodule