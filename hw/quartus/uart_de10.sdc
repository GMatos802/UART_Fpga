create_clock -name clk50 -period 20.000 [get_ports clk]
derive_clock_uncertainty
set_false_path -from [get_ports {rst tx_start loopback rx_ext data_in[*]}]
set_false_path -to [get_ports {tx_out rx_sample rx_ready tx_busy led data_out[*]}]
