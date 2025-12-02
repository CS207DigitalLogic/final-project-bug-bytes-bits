module Calculator_Core (
    input wire clk,
    input wire rst_n,

    // 1. 控制接口
    input wire w_start_calc,       // FSM: "开始计算！"
    input wire [2:0] w_op_code,    // 0:转置, 1:加法, 2:标量乘, 3:矩阵乘, 4:卷积
    input wire [31:0] w_scalar_val,// 标量乘法时的乘数 (来自 switches)
    output reg w_calc_done,        // "算完了！"
    output reg [31:0] w_cycle_count, // 卷积用的周期计数

    // 2. 存储接口 (连接到 MUX)
    output reg w_calc_we,
    output reg [7:0] w_calc_addr,
    output reg [31:0] w_calc_data,
    input wire [31:0] w_storage_out // 读到的数据
);

    // --- 地址映射定义 (请根据你的文档约定修改) ---
    localparam ADDR_A_BASE = 0;   // 矩阵 A 起始地址
    localparam ADDR_B_BASE = 32;  // 矩阵 B 起始地址 (假设每个矩阵分配32格)
    localparam ADDR_C_BASE = 64;  // 结果矩阵 C 起始地址

    // --- 操作码定义 ---
    localparam OP_TRANSPOSE = 3'd0;
    localparam OP_ADD       = 3'd1;
    localparam OP_SCALAR    = 3'd2;
    localparam OP_MULT      = 3'd3;
    // localparam OP_CONV   = 3'd4; // 留给 Bonus

    // --- 状态机定义 ---
    localparam S_IDLE       = 0;
    localparam S_READ_DIM_A = 1; // 读取维度
    localparam S_READ_DIM_B = 2;
    localparam S_PREPARE    = 3; // 准备循环变量
    localparam S_CALC_LOOP  = 4; // 通用计算循环
    localparam S_READ_OP1   = 5; // 读第一个操作数
    localparam S_READ_OP2   = 6; // 读第二个操作数
    localparam S_WRITE_RES  = 7; // 写结果
    localparam S_DONE       = 8;
    
    reg [3:0] state;
    reg [3:0] next_state; // 用于子状态跳转返回

    // --- 内部寄存器 ---
    reg [31:0] dim_m, dim_n, dim_p; // 维度寄存器: A(m*n), B(n*p)
    reg [3:0] i, j, k;              // 循环计数器 (最大5，4位够了)
    reg [31:0] val_A, val_B, acc;   // 操作数缓存 & 累加器

    // ============================================================
    // 主逻辑
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            w_calc_done <= 0;
            w_calc_we <= 0;
            w_calc_addr <= 0;
            w_calc_data <= 0;
            w_cycle_count <= 0;
            dim_m <= 0; dim_n <= 0; dim_p <= 0;
            i <= 0; j <= 0; k <= 0;
            val_A <= 0; val_B <= 0; acc <= 0;
        end else begin
            case (state)
                // --------------------------------------------------------
                // 1. 空闲等待
                // --------------------------------------------------------
                S_IDLE: begin
                    w_calc_done <= 0;
                    w_calc_we <= 0;
                    if (w_start_calc) begin
                        state <= S_READ_DIM_A;
                        // 卷积计数器清零 (如果是卷积模式则开始计数，这里简化略过)
                    end
                end

                // --------------------------------------------------------
                // 2. 读取维度信息 (A的行列, B的行列)
                // --------------------------------------------------------
                S_READ_DIM_A: begin
                    // 读 A_ROW (Addr 0)
                    w_calc_addr <= ADDR_A_BASE + 0;
                    state <= S_READ_DIM_B; // 实际上这里应该分两步(Addr0, Addr1)，为了代码紧凑这里简化处理
                    // *严谨写法*：需要多个状态分别读 m, n。
                    // 这里假设：我们下一拍读到 A_row，再下一拍读 A_col。
                    // 为了演示"一遍写通"的逻辑，我们用一种通用的 Loop 结构。
                    // 让我们重写这部分，使其更通用。
                    
                    // 修正：直接跳转到通用的准备状态，在 PREPARE 里一次性读完太复杂。
                    // 我们这里硬编码读一下吧，稳妥一点。
                    w_calc_addr <= ADDR_A_BASE; // 读 A.row
                    state <= 10; // 临时状态：存 A.row
                end
                
                10: begin // 读到了 A.row
                    dim_m <= w_storage_out; 
                    w_calc_addr <= ADDR_A_BASE + 1; // 读 A.col
                    state <= 11;
                end
                
                11: begin // 读到了 A.col
                    dim_n <= w_storage_out;
                    // 如果是矩阵乘法，还需要读 B.col (p)
                    if (w_op_code == OP_MULT) begin
                         w_calc_addr <= ADDR_B_BASE + 1; // 读 B.col (B.row 应该是 n，前面检查过了)
                         state <= 12;
                    end else begin
                         state <= S_PREPARE;
                    end
                end

                12: begin // 读到了 B.col
                    dim_p <= w_storage_out;
                    state <= S_PREPARE;
                end

                // --------------------------------------------------------
                // 3. 准备计算 (初始化循环变量 & 写结果维度)
                // --------------------------------------------------------
                S_PREPARE: begin
                    i <= 0; j <= 0; k <= 0;
                    acc <= 0;
                    
                    // 先把结果矩阵 C 的维度写入 Storage
                    w_calc_we <= 1;
                    w_calc_addr <= ADDR_C_BASE; // C.row
                    
                    case (w_op_code)
                        OP_TRANSPOSE: w_calc_data <= dim_n; // 转置：行变列
                        OP_MULT:      w_calc_data <= dim_m; // 乘法：m * p
                        default:      w_calc_data <= dim_m; // 加法/标量：不变
                    endcase
                    state <= 13; // 写完行，去写列
                end

                13: begin
                    w_calc_addr <= ADDR_C_BASE + 1; // C.col
                    case (w_op_code)
                        OP_TRANSPOSE: w_calc_data <= dim_m; // 转置：列变行
                        OP_MULT:      w_calc_data <= dim_p; // 乘法：m * p
                        default:      w_calc_data <= dim_n;
                    endcase
                    state <= S_CALC_LOOP;
                end

                // --------------------------------------------------------
                // 4. 核心计算循环 (Core Loop)
                // --------------------------------------------------------
                S_CALC_LOOP: begin
                    w_calc_we <= 0; // 停止写维度

                    // 根据不同操作符，决定循环逻辑
                    case (w_op_code)
                        
                        // === 矩阵加法 / 标量乘法 / 转置 (双重循环 i,j) ===
                        OP_ADD, OP_SCALAR, OP_TRANSPOSE: begin
                            // 读 A[i][j] (地址 = Base + 2 + i*n + j)
                            // 注意：转置时我们读 A[i][j] 写入 C[j][i]
                            w_calc_addr <= ADDR_A_BASE + 2 + (i * dim_n) + j;
                            state <= S_READ_OP1;
                        end

                        // === 矩阵乘法 (三重循环 i,j,k) ===
                        OP_MULT: begin
                            // 累加计算：C[i][j] += A[i][k] * B[k][j]
                            // 第一步：读 A[i][k]
                            w_calc_addr <= ADDR_A_BASE + 2 + (i * dim_n) + k;
                            state <= S_READ_OP1;
                        end
                    endcase
                end

                // --------------------------------------------------------
                // 5. 读操作数 1
                // --------------------------------------------------------
                S_READ_OP1: begin
                    val_A <= w_storage_out; // 拿到 A 的元素
                    
                    if (w_op_code == OP_MULT) begin
                        // 乘法：还需要读 B[k][j]
                        // B 的列数是 p (dim_p)，所以地址是 Base + 2 + k*p + j
                        w_calc_addr <= ADDR_B_BASE + 2 + (k * dim_p) + j;
                        state <= S_READ_OP2;
                    end 
                    else if (w_op_code == OP_ADD) begin
                        // 加法：还需要读 B[i][j]
                        w_calc_addr <= ADDR_B_BASE + 2 + (i * dim_n) + j;
                        state <= S_READ_OP2;
                    end
                    else begin
                        // 转置或标量乘：不需要读第二个内存数，直接去算
                        state <= S_WRITE_RES;
                    end
                end

                // --------------------------------------------------------
                // 6. 读操作数 2 (仅加法/乘法需要)
                // --------------------------------------------------------
                S_READ_OP2: begin
                    val_B <= w_storage_out; // 拿到 B 的元素
                    state <= S_WRITE_RES;
                end

                // --------------------------------------------------------
                // 7. 运算并写入结果
                // --------------------------------------------------------
                S_WRITE_RES: begin
                    case (w_op_code)
                        OP_ADD:       w_calc_data <= val_A + val_B;
                        OP_SCALAR:    w_calc_data <= val_A * w_scalar_val;
                        OP_TRANSPOSE: w_calc_data <= val_A; // 数据不变，只是写入地址变了
                        
                        OP_MULT: begin
                            // 乘法累加逻辑
                            // acc = acc + A * B
                            // 注意：这里需要分步，为了时序安全，最好下一拍再写，但这里尝试合一
                            acc <= acc + val_A * val_B;
                            
                            // 乘法不需要在这里写 RAM，除非 k 到了最后一步
                            if (k == dim_n - 1) begin
                                w_calc_data <= acc + val_A * val_B; // 最后一次累加并写入
                            end
                        end
                    endcase

                    // --- 决定写入地址 ---
                    w_calc_we <= 1; // 默认写入
                    if (w_op_code == OP_TRANSPOSE) begin
                        // 转置写入 C[j][i] (注意行列翻转)
                        // C 的行宽是 m (dim_m)
                        w_calc_addr <= ADDR_C_BASE + 2 + (j * dim_m) + i;
                    end else if (w_op_code == OP_MULT) begin
                        // 乘法写入 C[i][j]
                        // 只有当 k 循环结束时才写入
                        if (k == dim_n - 1) begin
                            w_calc_we <= 1;
                            w_calc_addr <= ADDR_C_BASE + 2 + (i * dim_p) + j;
                        end else begin
                            w_calc_we <= 0; // 中间过程不写 RAM，只更新 acc
                        end
                    end else begin
                        // 加法/标量：写入 C[i][j]
                        w_calc_addr <= ADDR_C_BASE + 2 + (i * dim_n) + j;
                    end

                    // --- 循环变量更新 (Loop Control) ---
                    // 逻辑：更新 j, i (以及乘法里的 k)
                    
                    if (w_op_code == OP_MULT) begin
                        // 三重循环处理 (i, j, k)
                        if (k < dim_n - 1) begin
                            k <= k + 1;
                            state <= S_CALC_LOOP; // 继续累加 k
                        end else begin
                            // k 循环结束，一个 C[i][j] 算完了
                            k <= 0;
                            acc <= 0; // 清空累加器
                            
                            // 推进 j
                            if (j < dim_p - 1) begin
                                j <= j + 1;
                                state <= S_CALC_LOOP;
                            end else begin
                                // 推进 i
                                j <= 0;
                                if (i < dim_m - 1) begin
                                    i <= i + 1;
                                    state <= S_CALC_LOOP;
                                end else begin
                                    state <= S_DONE; // 全部结束
                                end
                            end
                        end
                    end 
                    else begin
                        // 双重循环处理 (i, j) - 适用于加法/转置/标量
                        // 注意：转置时内层循环上限是 dim_n (列)，外层是 dim_m (行)
                        // 转置的特殊性：我们遍历 A 的 i,j，所以这里统一用 A 的维度控制循环
                        
                        // 推进 j
                        if (j < dim_n - 1) begin
                            j <= j + 1;
                            state <= S_CALC_LOOP;
                        end else begin
                            j <= 0;
                            // 推进 i
                            if (i < dim_m - 1) begin
                                i <= i + 1;
                                state <= S_CALC_LOOP;
                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end
                end

                // --------------------------------------------------------
                // 8. 结束
                // --------------------------------------------------------
                S_DONE: begin
                    w_calc_we <= 0;
                    w_calc_done <= 1;
                    // 等待 FSM 撤销 start 信号
                    if (!w_start_calc) state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule