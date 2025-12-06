module Calculator_Core (
    input clk,
    input w_start_calc,
    input[2:0] w_op_code,
    input[31:0] w_storage_out,
    output w_calc_we,
    output[7:0] w_calc_addr,
    output[31:0] w_calc_data,
    output w_calc_done,
    output[31:0] w_cycle_count,
    output w_gen_done
);
    
endmodule