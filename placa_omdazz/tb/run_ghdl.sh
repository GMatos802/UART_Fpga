#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ghdl -a --std=08 --workdir=build ../../hw/hdl/UART_TX.vhd ../../hw/hdl/UART_RX.vhd ../../hw/hdl/CMD_EXEC.vhd ../../hw/hdl/UART_TOP.vhd ../hdl/SEG7_SCAN.vhd ../hdl/BOARD_TOP.vhd tb_BOARD_TOP.vhd
ghdl -e --std=08 --workdir=build -o build/tb_BOARD_TOP tb_BOARD_TOP
ghdl -r --std=08 --workdir=build tb_BOARD_TOP --wave=build/tb_BOARD_TOP.ghw --ieee-asserts=disable-at-0
