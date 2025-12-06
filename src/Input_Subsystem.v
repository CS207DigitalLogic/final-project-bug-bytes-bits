module Input_Subsystem (
    input clk, rst_n, uart_rx, w_en_input,
    output reg w_input_we,
    output reg [7:0] w_input_addr,
    output reg [31:0] w_input_data,
    output reg w_rx_done,
    output reg w_error_flag
);
parameter ASC_0 = 48;
parameter ASC_SPACE = 32;
parameter ASC_CR = 13; // \r
parameter ASC_LF = 10; // \n

reg[31:0] current_value;

wire[7:0] rx_data; //用来接收uart输入的一个八位ascii字符
wire rx_pulse;//接收rx的信号，拉高代表新字符到了
    
uart_rx #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(115200) //例化uart模块传参数过程
) dut (  //例化uart模块连引脚
    .clk(clk),
    .rst_n(rst_n),
    .rx(uart_rx),             
    .rx_data(rx_data),  
    .rx_done(rx_pulse)        
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_value <= 0;
        w_input_addr <= 0;
        w_input_we <= 0;
        w_input_data <= 0;
        w_error_flag <= 0;
        w_rx_done <= 0;

    end
    else if (w_en_input) begin//FSM激活输入使能
        w_error_flag <= 0;
        w_input_we <= 0;
        if (rx_pulse) begin
            if (rx_data >= ASC_0 && rx_data <= ASC_0+9) //代表输入字符是数字0-9
                current_value <= current_value * 10 + (rx_data - ASC_0);//确保获取到多位输入情况，空格键结束输入
            else if (rx_data == ASC_SPACE || rx_data == ASC_CR || rx_data == ASC_LF) begin//空格结束一次输入，传递数据准备发送给存储
                w_input_data <= current_value;
                w_input_we <= 1;
                current_value <= 0;
                w_input_addr <= w_input_addr + 1;
            end
            else 
                w_error_flag <= 1; //若不是数字或空格则报错

        end
    end
    else begin //非使能清空临时值
        current_value <= 0;
        w_error_flag <= 0;
        w_input_we <= 0;
    end
end
endmodule