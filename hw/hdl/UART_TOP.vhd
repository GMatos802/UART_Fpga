library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_TOP is 
    clk, rst : in std_logic;
    rx : in std_logic;
    tx : out std_logic; 
end entity UART_TOP;

architecture rtl of UART_TOP is
    begin
    
end architecture rtl