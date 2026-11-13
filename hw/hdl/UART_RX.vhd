library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_RX is
    generic (
        CLK_FREQ   : positive := 50_000_000;
        BAUD       : positive := 9_600;
        OVERSAMPLE : positive := 16
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        rx_in     : in  std_logic;
        data_out  : out std_logic_vector(7 downto 0);
        rx_ready  : out std_logic;
        rx_sample : out std_logic
    );
end entity UART_RX;

architecture rtl of UART_RX is
    constant TICK_DIV : positive := (CLK_FREQ + BAUD * OVERSAMPLE / 2) / (BAUD * OVERSAMPLE);

    type state_t is (IDLE, START, START_OK, DATA, SAMPLE, STOP, LOAD, DONE);
    signal state, next_state : state_t;

    signal s_clr, s_en        : std_logic;
    signal bit_clr, bit_inc   : std_logic;
    signal sr_shift           : std_logic;
    signal dout_load          : std_logic;

    signal tick     : std_logic;
    signal rx_s     : std_logic;
    signal s_mid    : std_logic;
    signal s_end    : std_logic;
    signal bit_last : std_logic;

    signal sync     : std_logic_vector(1 downto 0);
    signal tick_cnt : integer range 0 to TICK_DIV - 1;
    signal s_cnt    : integer range 0 to OVERSAMPLE - 1;
    signal bit_cnt  : integer range 0 to 7;
    signal sr       : std_logic_vector(7 downto 0);
    signal dout     : std_logic_vector(7 downto 0);
begin
    ctrl_state : process (clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ctrl_next : process (state, tick, rx_s, s_mid, s_end, bit_last)
    begin
        next_state <= state;
        case state is
            when IDLE =>
                if rx_s = '0' then
                    next_state <= START;
                end if;
            when START =>
                if tick = '1' and s_mid = '1' then
                    if rx_s = '0' then
                        next_state <= START_OK;
                    else
                        next_state <= IDLE;
                    end if;
                end if;
            when START_OK =>
                next_state <= DATA;
            when DATA =>
                if tick = '1' and s_end = '1' then
                    next_state <= SAMPLE;
                end if;
            when SAMPLE =>
                if bit_last = '1' then
                    next_state <= STOP;
                else
                    next_state <= DATA;
                end if;
            when STOP =>
                if tick = '1' and s_end = '1' then
                    if rx_s = '1' then
                        next_state <= LOAD;
                    else
                        next_state <= IDLE;
                    end if;
                end if;
            when LOAD =>
                next_state <= DONE;
            when DONE =>
                next_state <= IDLE;
        end case;
    end process;

    ctrl_out : process (state)
    begin
        s_clr     <= '0';
        s_en      <= '0';
        bit_clr   <= '0';
        bit_inc   <= '0';
        sr_shift  <= '0';
        dout_load <= '0';
        rx_ready  <= '0';
        case state is
            when IDLE =>
                s_clr   <= '1';
                bit_clr <= '1';
            when START | DATA | STOP =>
                s_en <= '1';
            when START_OK =>
                s_clr <= '1';
            when SAMPLE =>
                s_clr    <= '1';
                bit_inc  <= '1';
                sr_shift <= '1';
            when LOAD =>
                dout_load <= '1';
            when DONE =>
                rx_ready <= '1';
        end case;
    end process;

    dp_regs : process (clk, rst)
    begin
        if rst = '1' then
            sync     <= (others => '1');
            tick_cnt <= 0;
            s_cnt    <= 0;
            bit_cnt  <= 0;
            sr       <= (others => '0');
            dout     <= (others => '0');
        elsif rising_edge(clk) then
            sync <= sync(0) & rx_in;

            if tick_cnt = TICK_DIV - 1 then
                tick_cnt <= 0;
            else
                tick_cnt <= tick_cnt + 1;
            end if;

            if s_clr = '1' then
                s_cnt <= 0;
            elsif s_en = '1' and tick = '1' then
                s_cnt <= (s_cnt + 1) mod OVERSAMPLE;
            end if;

            if bit_clr = '1' then
                bit_cnt <= 0;
            elsif bit_inc = '1' then
                bit_cnt <= (bit_cnt + 1) mod 8;
            end if;

            if sr_shift = '1' then
                sr <= rx_s & sr(7 downto 1);
            end if;

            if dout_load = '1' then
                dout <= sr;
            end if;
        end if;
    end process;

    rx_s     <= sync(1);
    tick     <= '1' when tick_cnt = TICK_DIV - 1 else '0';
    s_mid    <= '1' when s_cnt = OVERSAMPLE / 2 - 1 else '0';
    s_end    <= '1' when s_cnt = OVERSAMPLE - 1 else '0';
    bit_last <= '1' when bit_cnt = 7 else '0';
    data_out  <= dout;
    rx_sample <= sr_shift;
end architecture rtl;
