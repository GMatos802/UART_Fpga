library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SEG7_SCAN is
    generic (
        SCAN_BITS      : positive := 18;
        SEG_ACTIVE_LOW : boolean  := true;
        DIG_ACTIVE_LOW : boolean  := true
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        value : in  std_logic_vector(15 downto 0);
        dig   : out std_logic_vector(3 downto 0);
        seg   : out std_logic_vector(7 downto 0)
    );
end entity SEG7_SCAN;

architecture rtl of SEG7_SCAN is
    signal scan   : unsigned(SCAN_BITS - 1 downto 0);
    signal sel    : unsigned(1 downto 0);
    signal nibble : std_logic_vector(3 downto 0);
    signal seg_on : std_logic_vector(7 downto 0);
    signal dig_on : std_logic_vector(3 downto 0);
begin
    process (clk, rst)
    begin
        if rst = '1' then
            scan <= (others => '0');
        elsif rising_edge(clk) then
            scan <= scan + 1;
        end if;
    end process;

    sel <= scan(SCAN_BITS - 1 downto SCAN_BITS - 2);

    with sel select
        nibble <= value(15 downto 12) when "00",
                  value(11 downto 8)  when "01",
                  value(7 downto 4)   when "10",
                  value(3 downto 0)   when others;

    with sel select
        dig_on <= "0001" when "00",
                  "0010" when "01",
                  "0100" when "10",
                  "1000" when others;

    with nibble select
        seg_on <= "00111111" when x"0",
                  "00000110" when x"1",
                  "01011011" when x"2",
                  "01001111" when x"3",
                  "01100110" when x"4",
                  "01101101" when x"5",
                  "01111101" when x"6",
                  "00000111" when x"7",
                  "01111111" when x"8",
                  "01101111" when x"9",
                  "01110111" when x"A",
                  "01111100" when x"B",
                  "00111001" when x"C",
                  "01011110" when x"D",
                  "01111001" when x"E",
                  "01110001" when others;

    seg <= not seg_on when SEG_ACTIVE_LOW else seg_on;
    dig <= not dig_on when DIG_ACTIVE_LOW else dig_on;
end architecture rtl;
