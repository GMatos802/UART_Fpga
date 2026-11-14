library ieee;
use ieee.std_logic_1164.all;

entity PIN_FINDER is
    port (
        CLK     : in  std_logic;
        RESET_N : in  std_logic;
        P       : in  std_logic_vector(0 to 22);
        LED     : out std_logic_vector(4 downto 1);
        DIG     : out std_logic_vector(4 downto 1);
        SEG     : out std_logic_vector(7 downto 0)
    );
end entity PIN_FINDER;

architecture rtl of PIN_FINDER is
    type nums_t is array (0 to 22) of std_logic_vector(15 downto 0);
    constant NUMS : nums_t := (
        x"0141", x"0138", x"0143", x"0142", x"0001", x"0144", x"0003", x"0002",
        x"0010", x"0007", x"0011",
        x"0098", x"0099", x"0112", x"0113",
        x"0119", x"0120",
        x"0100",
        x"0101", x"0103", x"0104", x"0105", x"0106"
    );

    signal rst     : std_logic;
    signal sync1   : std_logic_vector(0 to 22);
    signal sync2   : std_logic_vector(0 to 22);
    signal found   : std_logic_vector(15 downto 0);
    signal any_low : std_logic;
    signal dig_i   : std_logic_vector(3 downto 0);
begin
    rst <= not RESET_N;

    process (CLK, rst)
    begin
        if rst = '1' then
            sync1 <= (others => '1');
            sync2 <= (others => '1');
        elsif rising_edge(CLK) then
            sync1 <= P;
            sync2 <= sync1;
        end if;
    end process;

    process (sync2)
    begin
        found   <= x"0000";
        any_low <= '0';
        for i in 22 downto 0 loop
            if sync2(i) = '0' then
                found   <= NUMS(i);
                any_low <= '1';
            end if;
        end loop;
    end process;

    u_display : entity work.SEG7_SCAN
        port map (
            clk   => CLK,
            rst   => rst,
            value => found,
            dig   => dig_i,
            seg   => SEG
        );

    DIG <= dig_i(0) & dig_i(1) & dig_i(2) & dig_i(3);
    LED <= "111" & not any_low;
end architecture rtl;
