create_clock -name clk50 -period 20.000 [get_ports CLK]
derive_clock_uncertainty
set_false_path -from [get_ports {RESET_N KEY1 KEY2 UART_RXD ESP32_TX2}]
set_false_path -to [get_ports {LED[*] DIG[*] SEG[*] UART_TXD ESP32_RX2 DBG_*}]
