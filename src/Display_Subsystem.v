module Display_Subsystem (
    input wire clk,
    input wire rst_n,

    // ============================================
    // 1. 来自 FSM 的控制与信息接口
    // ============================================
    input wire w_en_display,          // 【控制】启动信号
    
    // 模式选择：
    // 0 = 仅显示单矩阵 (用于回显确认、显示结果)
    // 1 = 显示选择列表 (用于运算数选择，显示 ID + 矩阵内容)
    // 2 = 显示汇总摘要 (主菜单的 "3 2*2*1...")
    input wire [1:0] w_disp_mode,

    // 矩阵的核心参数 (FSM 查表后传给 Display)
    input wire [31:0] w_disp_m,       // 矩阵行数
    input wire [31:0] w_disp_n,       // 矩阵列数
    input wire [7:0]  w_disp_base_addr, // 该规格矩阵在 Storage 中的【起始基地址】
                                      // 注意：这是第 1 个矩阵的地址。
                                      // Display 模块需自行计算第 2 个矩阵的偏移。
    
    input wire [1:0]  w_disp_total_cnt, // 该规格共有几个矩阵? (0, 1, 2)
                                        // 决定了列表显示要循环几次

    // ============================================
    // 2. Storage 交互接口 (读数据)
    // ============================================
    // Display 发出地址，Storage 下一周期返回数据
    output reg [7:0]  w_disp_req_addr,  // 发给 Storage 的读地址
    input wire [31:0] w_storage_rdata,  // 从 Storage 读回的数据

    // ============================================
    // 3. UART 发送接口
    // ============================================
    input wire w_tx_ready,            // UART: "我空闲了，可以发"
    output reg [7:0]  w_disp_tx_data, // Display: "要发的 ASCII 字符"
    output reg        w_disp_tx_en,   // Display: "发送脉冲"

    // ============================================
    // 4. 握手反馈
    // ============================================
    output reg w_disp_done            // "老板，显示任务全部完成"
);

    // 参数定义 (建议放在 module 内部)
    localparam MODE_SINGLE = 2'd0;
    localparam MODE_LIST   = 2'd1;
    localparam MODE_SUMMARY= 2'd2;

    // ... 内部逻辑 ...

endmodule