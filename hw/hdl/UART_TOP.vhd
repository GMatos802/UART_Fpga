entity UART_TOP is 
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        tx_start : in  std_logic;
        data_in  : in  std_logic_vector(7 downto 0);
        tx_out   : out std_logic;
        data_out : out std_logic_vector(7 downto 0);
        tx_busy  : out std_logic;
        rx_ready : out std_logic
    );
end entity UART_TOP;