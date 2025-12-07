module Storage_Mux (
    // =======================================
    // 1. 仲裁选择信号 (来自 FSM)
    // =======================================
    input wire i_en_input,      // 对应 FSM 的 w_en_input
    input wire i_en_display,    // 对应 FSM 的 w_en_display
    input wire i_en_calc,       // 对应 FSM 的 w_start_calc (计算期间为高)

    // =======================================
    // 2. 各子模块接口 (Inputs)
    // =======================================
    // Input Subsystem
    input wire [7:0]  i_input_addr, // 对应 w_real_addr
    input wire [31:0] i_input_data, // 对应 w_input_data
    input wire        i_input_we,   // 对应 w_input_we

    // Display Subsystem (只读，无写信号)
    input wire [7:0]  i_disp_addr,  // 对应 w_disp_req_addr

    // Calculator Core
    input wire [7:0]  i_calc_addr,  // 对应 w_calc_addr
    input wire [31:0] i_calc_data,  // 对应 w_calc_data
    input wire        i_calc_we,    // 对应 w_calc_we

    // =======================================
    // 3. 输出到 Storage (Outputs)
    // =======================================
    output reg [7:0]  o_storage_addr,
    output reg [31:0] o_storage_data,
    output reg        o_storage_we
);

    // 组合逻辑 MUX
    always @(*) begin
        // 优先级逻辑 (基于 FSM 状态互斥)
        // 模式 1: 输入/生成模式
        if (i_en_input) begin
            o_storage_addr = i_input_addr;
            o_storage_data = i_input_data;
            o_storage_we   = i_input_we;
        end
        // 模式 2: 展示模式 (读操作)
        else if (i_en_display) begin
            o_storage_addr = i_disp_addr;
            o_storage_data = 32'd0; // 读模式下数据线置0即可
            o_storage_we   = 1'b0;  // 读模式，禁止写入
        end
        // 模式 3: 计算模式
        else if (i_en_calc) begin
            o_storage_addr = i_calc_addr;
            o_storage_data = i_calc_data;
            o_storage_we   = i_calc_we;
        end
        // 默认/空闲状态
        else begin
            o_storage_addr = 8'd0;
            o_storage_data = 32'd0;
            o_storage_we   = 1'b0;
        end
    end

endmodule