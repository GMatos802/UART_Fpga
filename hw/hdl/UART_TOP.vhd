library ieee;
use ieee.std_logic_1164.all;

entity UART_TOP is
    generic (
        CLK_FREQ   : positive := 50_000_000;
        BAUD       : positive := 9_600;
        OVERSAMPLE : positive := 16
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tx_start  : in  std_logic;
        data_in   : in  std_logic_vector(7 downto 0);
        tx_out    : out std_logic;
        data_out  : out std_logic_vector(7 downto 0);
        tx_busy   : out std_logic;
        rx_ready  : out std_logic;
        rx_sample : out std_logic
    );
end entity UART_TOP;

architecture structural of UART_TOP is
    signal rst_i      : std_logic;
    signal tx_start_i : std_logic;
    signal serial     : std_logic;
begin
    rst_i      <= not rst;
    tx_start_i <= not tx_start;

    u_tx : entity work.UART_TX
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD     => BAUD
        )
        port map (
            clk      => clk,
            rst      => rst_i,
            tx_start => tx_start_i,
            data_in  => data_in,
            tx_out   => serial,
            tx_busy  => tx_busy
        );

    u_rx : entity work.UART_RX
        generic map (
            CLK_FREQ   => CLK_FREQ,
            BAUD       => BAUD,
            OVERSAMPLE => OVERSAMPLE
        )
        port map (
            clk       => clk,
            rst       => rst_i,
            rx_in     => serial,
            data_out  => data_out,
            rx_ready  => rx_ready,
            rx_sample => rx_sample
        );

    tx_out <= serial;
end architecture structural;
