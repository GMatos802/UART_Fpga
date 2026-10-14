library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_TX is 
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        tx_start : in  std_logic;
        data_in  : in  std_logic_vector(7 downto 0);
        tx_out   : out std_logic;
        tx_busy  : out std_logic
    );
end entity UART_TX;

architecture rtl of UART_TX is
begin

end architecture rtl;