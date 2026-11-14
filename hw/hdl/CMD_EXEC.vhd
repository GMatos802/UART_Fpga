library ieee;
use ieee.std_logic_1164.all;

entity CMD_EXEC is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        rx_data  : in  std_logic_vector(7 downto 0);
        rx_ready : in  std_logic;
        tx_busy  : in  std_logic;
        btn      : in  std_logic;
        sw_data  : in  std_logic_vector(7 downto 0);
        tx_start : out std_logic;
        tx_data  : out std_logic_vector(7 downto 0);
        led      : out std_logic
    );
end entity CMD_EXEC;

architecture rtl of CMD_EXEC is
    constant BYTE_START : std_logic_vector(7 downto 0) := x"23";
    constant CMD_ON     : std_logic_vector(7 downto 0) := x"4C";
    constant CMD_OFF    : std_logic_vector(7 downto 0) := x"44";
    constant CODE_ON    : std_logic_vector(7 downto 0) := x"31";
    constant CODE_OFF   : std_logic_vector(7 downto 0) := x"30";
    constant CODE_ERR   : std_logic_vector(7 downto 0) := x"45";

    type state_t is (IDLE, WAIT_CMD, SAVE_CMD, WAIT_CHK, LED_ON, LED_OFF, CMD_ERR, WAIT_TX, SEND);
    signal state, next_state : state_t;

    signal cmd_load            : std_logic;
    signal led_set, led_clr    : std_logic;
    signal resp_on, resp_off   : std_logic;
    signal resp_err            : std_logic;
    signal ack_start, ack_sel  : std_logic;

    signal is_start : std_logic;
    signal chk_ok   : std_logic;
    signal is_on    : std_logic;
    signal is_off   : std_logic;

    signal cmd   : std_logic_vector(7 downto 0);
    signal resp  : std_logic_vector(7 downto 0);
    signal led_q : std_logic;
begin
    ctrl_state : process (clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
        elsif rising_edge(clk) then
            state <= next_state;
        end if;
    end process;

    ctrl_next : process (state, rx_ready, is_start, chk_ok, is_on, is_off, tx_busy)
    begin
        next_state <= state;
        case state is
            when IDLE =>
                if rx_ready = '1' and is_start = '1' then
                    next_state <= WAIT_CMD;
                end if;
            when WAIT_CMD =>
                if rx_ready = '1' then
                    next_state <= SAVE_CMD;
                end if;
            when SAVE_CMD =>
                next_state <= WAIT_CHK;
            when WAIT_CHK =>
                if rx_ready = '1' then
                    if chk_ok = '1' and is_on = '1' then
                        next_state <= LED_ON;
                    elsif chk_ok = '1' and is_off = '1' then
                        next_state <= LED_OFF;
                    else
                        next_state <= CMD_ERR;
                    end if;
                end if;
            when LED_ON | LED_OFF | CMD_ERR =>
                next_state <= WAIT_TX;
            when WAIT_TX =>
                if tx_busy = '0' then
                    next_state <= SEND;
                end if;
            when SEND =>
                if tx_busy = '1' then
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    ctrl_out : process (state)
    begin
        cmd_load  <= '0';
        led_set   <= '0';
        led_clr   <= '0';
        resp_on   <= '0';
        resp_off  <= '0';
        resp_err  <= '0';
        ack_start <= '0';
        ack_sel   <= '0';
        case state is
            when SAVE_CMD =>
                cmd_load <= '1';
            when LED_ON =>
                led_set <= '1';
                resp_on <= '1';
            when LED_OFF =>
                led_clr  <= '1';
                resp_off <= '1';
            when CMD_ERR =>
                resp_err <= '1';
            when SEND =>
                ack_start <= '1';
                ack_sel   <= '1';
            when IDLE | WAIT_CMD | WAIT_CHK | WAIT_TX =>
                null;
        end case;
    end process;

    dp_regs : process (clk, rst)
    begin
        if rst = '1' then
            cmd   <= (others => '0');
            resp  <= (others => '0');
            led_q <= '0';
        elsif rising_edge(clk) then
            if cmd_load = '1' then
                cmd <= rx_data;
            end if;

            if resp_on = '1' then
                resp <= CODE_ON;
            elsif resp_off = '1' then
                resp <= CODE_OFF;
            elsif resp_err = '1' then
                resp <= CODE_ERR;
            end if;

            if led_set = '1' then
                led_q <= '1';
            elsif led_clr = '1' then
                led_q <= '0';
            end if;
        end if;
    end process;

    is_start <= '1' when rx_data = BYTE_START else '0';
    chk_ok   <= '1' when rx_data = not cmd else '0';
    is_on    <= '1' when cmd = CMD_ON else '0';
    is_off   <= '1' when cmd = CMD_OFF else '0';

    tx_start <= btn or ack_start;
    tx_data  <= resp when ack_sel = '1' else sw_data;
    led      <= led_q;
end architecture rtl;
