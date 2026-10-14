library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_TOP is 
    clk, rst : in std_logic;
    tx_start : in std_logic;
    data_in : in std_logic_vector(7 downto 0);
    tx_out : out std_logic_vector(8 downto 0);
    tx_busy : out std_logic;
end entity UART_TOP;

architecture rtl of UART_TOP is
    begin
    
end architecture rtl