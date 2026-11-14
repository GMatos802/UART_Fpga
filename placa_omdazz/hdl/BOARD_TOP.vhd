library ieee;
use ieee.std_logic_1164.all;

entity BOARD_TOP is
    generic (
        CLK_FREQ       : positive                     := 50_000_000;
        BAUD           : positive                     := 9_600;
        TX_BYTE        : std_logic_vector(7 downto 0) := x"53";
        RX_FROM_USB    : boolean                      := false;
        LED_ACTIVE_LOW : boolean                      := true;
        SEG_ACTIVE_LOW : boolean                      := true;
        DIG_ACTIVE_LOW : boolean                      := true
    );
    port (
        CLK           : in  std_logic;
        RESET_N       : in  std_logic;
        KEY1          : in  std_logic;
        KEY2          : in  std_logic;
        LED           : out std_logic_vector(4 downto 1);
        DIG           : out std_logic_vector(4 downto 1);
        SEG           : out std_logic_vector(7 downto 0);
        UART_TXD      : out std_logic;
        UART_RXD      : in  std_logic;
        ESP32_TX2     : in  std_logic;
        ESP32_RX2     : out std_logic;
        DBG_RX_SAMPLE : out std_logic;
        DBG_RX_READY  : out std_logic;
        DBG_TX_BUSY   : out std_logic
    );
end entity BOARD_TOP;

architecture structural of BOARD_TOP is
    signal rst_i    : std_logic;
    signal loopback : std_logic;
    signal rx_ext   : std_logic;
    signal tx_out   : std_logic;
    signal data_out : std_logic_vector(7 downto 0);
    signal cmd_led  : std_logic;
    signal leds     : std_logic_vector(4 downto 1);
    signal display  : std_logic_vector(15 downto 0);
    signal dig_i    : std_logic_vector(3 downto 0);
begin
    rst_i    <= not RESET_N;
    loopback <= not KEY2;
    rx_ext   <= UART_RXD when RX_FROM_USB else ESP32_TX2;

    u_uart : entity work.UART_TOP
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD     => BAUD
        )
        port map (
            clk       => CLK,
            rst       => RESET_N,
            tx_start  => KEY1,
            data_in   => TX_BYTE,
            loopback  => loopback,
            rx_ext    => rx_ext,
            tx_out    => tx_out,
            data_out  => data_out,
            tx_busy   => DBG_TX_BUSY,
            rx_ready  => DBG_RX_READY,
            rx_sample => DBG_RX_SAMPLE,
            led       => cmd_led
        );

    u_display : entity work.SEG7_SCAN
        generic map (
            SEG_ACTIVE_LOW => SEG_ACTIVE_LOW,
            DIG_ACTIVE_LOW => DIG_ACTIVE_LOW
        )
        port map (
            clk   => CLK,
            rst   => rst_i,
            value => display,
            dig   => dig_i,
            seg   => SEG
        );

    display <= TX_BYTE & data_out;
    DIG     <= dig_i(0) & dig_i(1) & dig_i(2) & dig_i(3);

    leds(1) <= loopback;
    leds(2) <= '0';
    leds(3) <= '0';
    leds(4) <= cmd_led;

    LED       <= not leds when LED_ACTIVE_LOW else leds;
    UART_TXD  <= tx_out;
    ESP32_RX2 <= tx_out;
end architecture structural;
