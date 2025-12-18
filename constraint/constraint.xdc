create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk1]
set_property PACKAGE_PIN P17 [get_ports clk1]
set_property IOSTANDARD LVCMOS33 [get_ports clk1]


set_property PACKAGE_PIN P5 [get_ports {sw[7]}]
set_property PACKAGE_PIN P4 [get_ports {sw[6]}]
set_property PACKAGE_PIN P3 [get_ports {sw[5]}]
set_property PACKAGE_PIN P2 [get_ports {sw[4]}]
set_property PACKAGE_PIN R2 [get_ports {sw[3]}]
set_property PACKAGE_PIN M4 [get_ports {sw[2]}]
set_property PACKAGE_PIN N4 [get_ports {sw[1]}]
set_property PACKAGE_PIN R1 [get_ports {sw[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

set_property PACKAGE_PIN U4 [get_ports {btn[4]}]
set_property PACKAGE_PIN V1 [get_ports {btn[3]}]
set_property PACKAGE_PIN R15 [get_ports {btn[2]}]
set_property PACKAGE_PIN R17 [get_ports {btn[1]}]
set_property PACKAGE_PIN R11 [get_ports {btn[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {btn[*]}]

set_property PACKAGE_PIN N5 [get_ports uart_rx]
set_property PACKAGE_PIN T4 [get_ports uart_tx]

set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]


set_property PACKAGE_PIN F6 [get_ports {led[7]}]
set_property PACKAGE_PIN G4 [get_ports {led[6]}]
set_property PACKAGE_PIN G3 [get_ports {led[5]}]
set_property PACKAGE_PIN J4 [get_ports {led[4]}]
set_property PACKAGE_PIN H4 [get_ports {led[3]}]
set_property PACKAGE_PIN J3 [get_ports {led[2]}]
set_property PACKAGE_PIN J2 [get_ports {led[1]}]
set_property PACKAGE_PIN K2 [get_ports {led[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]


set_property PACKAGE_PIN B4 [get_ports {seg[7]}]
set_property PACKAGE_PIN A4 [get_ports {seg[6]}]
set_property PACKAGE_PIN A3 [get_ports {seg[5]}]
set_property PACKAGE_PIN B1 [get_ports {seg[4]}]
set_property PACKAGE_PIN A1 [get_ports {seg[3]}]
set_property PACKAGE_PIN B3 [get_ports {seg[2]}]
set_property PACKAGE_PIN B2 [get_ports {seg[1]}]
set_property PACKAGE_PIN D5 [get_ports {seg[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]


set_property PACKAGE_PIN G2 [get_ports {an[0]}]
set_property PACKAGE_PIN C2 [get_ports {an[1]}]
set_property PACKAGE_PIN C1 [get_ports {an[2]}]
set_property PACKAGE_PIN H1 [get_ports {an[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]




create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 9 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {w_input_addr[0]} {w_input_addr[1]} {w_input_addr[2]} {w_input_addr[3]} {w_input_addr[4]} {w_input_addr[5]} {w_input_addr[6]} {w_input_addr[7]} {w_input_addr[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 9 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {w_storage_addr[0]} {w_storage_addr[1]} {w_storage_addr[2]} {w_storage_addr[3]} {w_storage_addr[4]} {w_storage_addr[5]} {w_storage_addr[6]} {w_storage_addr[7]} {w_storage_addr[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {w_storage_wdata[0]} {w_storage_wdata[1]} {w_storage_wdata[2]} {w_storage_wdata[3]} {w_storage_wdata[4]} {w_storage_wdata[5]} {w_storage_wdata[6]} {w_storage_wdata[7]} {w_storage_wdata[8]} {w_storage_wdata[9]} {w_storage_wdata[10]} {w_storage_wdata[11]} {w_storage_wdata[12]} {w_storage_wdata[13]} {w_storage_wdata[14]} {w_storage_wdata[15]} {w_storage_wdata[16]} {w_storage_wdata[17]} {w_storage_wdata[18]} {w_storage_wdata[19]} {w_storage_wdata[20]} {w_storage_wdata[21]} {w_storage_wdata[22]} {w_storage_wdata[23]} {w_storage_wdata[24]} {w_storage_wdata[25]} {w_storage_wdata[26]} {w_storage_wdata[27]} {w_storage_wdata[28]} {w_storage_wdata[29]} {w_storage_wdata[30]} {w_storage_wdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 32 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {w_storage_rdata[0]} {w_storage_rdata[1]} {w_storage_rdata[2]} {w_storage_rdata[3]} {w_storage_rdata[4]} {w_storage_rdata[5]} {w_storage_rdata[6]} {w_storage_rdata[7]} {w_storage_rdata[8]} {w_storage_rdata[9]} {w_storage_rdata[10]} {w_storage_rdata[11]} {w_storage_rdata[12]} {w_storage_rdata[13]} {w_storage_rdata[14]} {w_storage_rdata[15]} {w_storage_rdata[16]} {w_storage_rdata[17]} {w_storage_rdata[18]} {w_storage_rdata[19]} {w_storage_rdata[20]} {w_storage_rdata[21]} {w_storage_rdata[22]} {w_storage_rdata[23]} {w_storage_rdata[24]} {w_storage_rdata[25]} {w_storage_rdata[26]} {w_storage_rdata[27]} {w_storage_rdata[28]} {w_storage_rdata[29]} {w_storage_rdata[30]} {w_storage_rdata[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 9 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_input/w_real_addr[0]} {u_input/w_real_addr[1]} {u_input/w_real_addr[2]} {u_input/w_real_addr[3]} {u_input/w_real_addr[4]} {u_input/w_real_addr[5]} {u_input/w_real_addr[6]} {u_input/w_real_addr[7]} {u_input/w_real_addr[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 9 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_fsm/w_base_addr_to_input[0]} {u_fsm/w_base_addr_to_input[1]} {u_fsm/w_base_addr_to_input[2]} {u_fsm/w_base_addr_to_input[3]} {u_fsm/w_base_addr_to_input[4]} {u_fsm/w_base_addr_to_input[5]} {u_fsm/w_base_addr_to_input[6]} {u_fsm/w_base_addr_to_input[7]} {u_fsm/w_base_addr_to_input[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 9 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_fsm/free_ptr[0]} {u_fsm/free_ptr[1]} {u_fsm/free_ptr[2]} {u_fsm/free_ptr[3]} {u_fsm/free_ptr[4]} {u_fsm/free_ptr[5]} {u_fsm/free_ptr[6]} {u_fsm/free_ptr[7]} {u_fsm/free_ptr[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 5 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_fsm/lut_count[0]} {u_fsm/lut_count[1]} {u_fsm/lut_count[2]} {u_fsm/lut_count[3]} {u_fsm/lut_count[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 32 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_display/r_cached_n[0]} {u_display/r_cached_n[1]} {u_display/r_cached_n[2]} {u_display/r_cached_n[3]} {u_display/r_cached_n[4]} {u_display/r_cached_n[5]} {u_display/r_cached_n[6]} {u_display/r_cached_n[7]} {u_display/r_cached_n[8]} {u_display/r_cached_n[9]} {u_display/r_cached_n[10]} {u_display/r_cached_n[11]} {u_display/r_cached_n[12]} {u_display/r_cached_n[13]} {u_display/r_cached_n[14]} {u_display/r_cached_n[15]} {u_display/r_cached_n[16]} {u_display/r_cached_n[17]} {u_display/r_cached_n[18]} {u_display/r_cached_n[19]} {u_display/r_cached_n[20]} {u_display/r_cached_n[21]} {u_display/r_cached_n[22]} {u_display/r_cached_n[23]} {u_display/r_cached_n[24]} {u_display/r_cached_n[25]} {u_display/r_cached_n[26]} {u_display/r_cached_n[27]} {u_display/r_cached_n[28]} {u_display/r_cached_n[29]} {u_display/r_cached_n[30]} {u_display/r_cached_n[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 32 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {u_display/r_cached_m[0]} {u_display/r_cached_m[1]} {u_display/r_cached_m[2]} {u_display/r_cached_m[3]} {u_display/r_cached_m[4]} {u_display/r_cached_m[5]} {u_display/r_cached_m[6]} {u_display/r_cached_m[7]} {u_display/r_cached_m[8]} {u_display/r_cached_m[9]} {u_display/r_cached_m[10]} {u_display/r_cached_m[11]} {u_display/r_cached_m[12]} {u_display/r_cached_m[13]} {u_display/r_cached_m[14]} {u_display/r_cached_m[15]} {u_display/r_cached_m[16]} {u_display/r_cached_m[17]} {u_display/r_cached_m[18]} {u_display/r_cached_m[19]} {u_display/r_cached_m[20]} {u_display/r_cached_m[21]} {u_display/r_cached_m[22]} {u_display/r_cached_m[23]} {u_display/r_cached_m[24]} {u_display/r_cached_m[25]} {u_display/r_cached_m[26]} {u_display/r_cached_m[27]} {u_display/r_cached_m[28]} {u_display/r_cached_m[29]} {u_display/r_cached_m[30]} {u_display/r_cached_m[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list u_fsm/w_addr_ready]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list u_fsm/w_dims_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list u_fsm/w_id_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list w_storage_we]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_BUFG]
