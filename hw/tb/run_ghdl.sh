#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ghdl -a --std=08 --workdir=build ../hdl/UART_TX.vhd ../hdl/UART_RX.vhd ../hdl/UART_TOP.vhd tb_UART_TOP.vhd
ghdl -e --std=08 --workdir=build -o build/tb_UART_TOP tb_UART_TOP
ghdl -r --std=08 --workdir=build tb_UART_TOP --wave=build/tb_UART_TOP.ghw --ieee-asserts=disable-at-0
