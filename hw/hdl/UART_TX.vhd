library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_TX is
    generic (
        CLK_FREQ : positive := 50_000_000;
        BAUD     : positive := 9_600
    );
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
    constant BAUD_DIV : positive := (CLK_FREQ + BAUD / 2) / BAUD;

    type state_t is (IDLE, START, START_END, DATA, SHIFT, STOP);
    signal state, next_state : state_t;

    signal cnt_clr, cnt_inc     : std_logic;
    signal bit_clr, bit_inc     : std_logic;
    signal sr_load, sr_shift    : std_logic;
    signal sel_start, sel_data  : std_logic;

    signal tx_start_s    : std_logic;
    signal cnt_last      : std_logic;
    signal cnt_stop_last : std_logic;
    signal bit_last      : std_logic;

    signal start_sync : std_logic_vector(1 downto 0);
    signal cnt     : integer range 0 to BAUD_DIV;
    signal bit_cnt : integer range 0 to 7;
    signal sr      : std_logic_vector(7 downto 0);
begin
    ctrl_state : process (clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ctrl_next : process (state, tx_start_s, cnt_last, cnt_stop_last, bit_last)
    begin
        next_state <= state;
        case state is
            when IDLE =>
                if tx_start_s = '1' then
                    next_state <= START;
                end if;
            when START =>
                if cnt_last = '1' then
                    next_state <= START_END;
                end if;
            when START_END =>
                next_state <= DATA;
            when DATA =>
                if cnt_last = '1' then
                    next_state <= SHIFT;
                end if;
            when SHIFT =>
                if bit_last = '1' then
                    next_state <= STOP;
                else
                    next_state <= DATA;
                end if;
            when STOP =>
                if cnt_stop_last = '1' then
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    ctrl_out : process (state)
    begin
        cnt_clr   <= '0';
        cnt_inc   <= '0';
        bit_clr   <= '0';
        bit_inc   <= '0';
        sr_load   <= '0';
        sr_shift  <= '0';
        sel_start <= '0';
        sel_data  <= '0';
        tx_busy   <= '1';
        case state is
            when IDLE =>
                cnt_clr <= '1';
                bit_clr <= '1';
                sr_load <= '1';
                tx_busy <= '0';
            when START =>
                cnt_inc   <= '1';
                sel_start <= '1';
            when START_END =>
                cnt_clr   <= '1';
                sel_start <= '1';
            when DATA =>
                cnt_inc  <= '1';
                sel_data <= '1';
            when SHIFT =>
                cnt_clr  <= '1';
                bit_inc  <= '1';
                sr_shift <= '1';
                sel_data <= '1';
            when STOP =>
                cnt_inc <= '1';
        end case;
    end process;

    dp_regs : process (clk, rst)
    begin
        if rst = '1' then
            start_sync <= (others => '0');
            cnt     <= 0;
            bit_cnt <= 0;
            sr      <= (others => '0');
        elsif rising_edge(clk) then
            start_sync <= start_sync(0) & tx_start;

            if cnt_clr = '1' then
                cnt <= 0;
            elsif cnt_inc = '1' then
                cnt <= cnt + 1;
            end if;

            if bit_clr = '1' then
                bit_cnt <= 0;
            elsif bit_inc = '1' then
                bit_cnt <= (bit_cnt + 1) mod 8;
            end if;

            if sr_load = '1' then
                sr <= data_in;
            elsif sr_shift = '1' then
                sr <= '0' & sr(7 downto 1);
            end if;
        end if;
    end process;

    tx_start_s    <= start_sync(1);
    cnt_last      <= '1' when cnt = BAUD_DIV - 2 else '0';
    cnt_stop_last <= '1' when cnt = BAUD_DIV - 1 else '0';
    bit_last      <= '1' when bit_cnt = 7 else '0';

    tx_out <= '0'   when sel_start = '1' else
              sr(0) when sel_data = '1' else
              '1';
end architecture rtl;
