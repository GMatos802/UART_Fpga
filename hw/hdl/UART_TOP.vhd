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
        loopback  : in  std_logic;
        rx_ext    : in  std_logic;
        tx_out    : out std_logic;
        data_out  : out std_logic_vector(7 downto 0);
        tx_busy   : out std_logic;
        rx_ready  : out std_logic;
        rx_sample : out std_logic;
        led       : out std_logic
    );
end entity UART_TOP;

architecture structural of UART_TOP is
    signal rst_i      : std_logic;
    signal btn_i      : std_logic;
    signal serial     : std_logic;
    signal rx_line    : std_logic;
    signal tx_start_i : std_logic;
    signal tx_data_i  : std_logic_vector(7 downto 0);
    signal tx_busy_i  : std_logic;
    signal rx_data_i  : std_logic_vector(7 downto 0);
    signal rx_ready_i : std_logic;
begin
    rst_i   <= not rst;
    btn_i   <= not tx_start;
    rx_line <= serial when loopback = '1' else rx_ext;

    u_tx : entity work.UART_TX
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD     => BAUD
        )
        port map (
            clk      => clk,
            rst      => rst_i,
            tx_start => tx_start_i,
            data_in  => tx_data_i,
            tx_out   => serial,
            tx_busy  => tx_busy_i
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
            rx_in     => rx_line,
            data_out  => rx_data_i,
            rx_ready  => rx_ready_i,
            rx_sample => rx_sample
        );

    u_cmd : entity work.CMD_EXEC
        port map (
            clk      => clk,
            rst      => rst_i,
            rx_data  => rx_data_i,
            rx_ready => rx_ready_i,
            tx_busy  => tx_busy_i,
            btn      => btn_i,
            sw_data  => data_in,
            tx_start => tx_start_i,
            tx_data  => tx_data_i,
            led      => led
        );

    tx_out   <= serial;
    tx_busy  <= tx_busy_i;
    data_out <= rx_data_i;
    rx_ready <= rx_ready_i;
end architecture structural;
