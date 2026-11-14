library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_BOARD_TOP is
end entity tb_BOARD_TOP;

architecture sim of tb_BOARD_TOP is
    constant T_CLK : time := 20 ns;
    constant T_BIT : time := 1 sec / 9600;

    type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    signal clk       : std_logic := '0';
    signal reset_n   : std_logic := '0';
    signal key1      : std_logic := '1';
    signal key2      : std_logic := '1';
    signal led       : std_logic_vector(4 downto 1);
    signal dig       : std_logic_vector(4 downto 1);
    signal seg       : std_logic_vector(7 downto 0);
    signal uart_txd  : std_logic;
    signal esp_tx2   : std_logic := '1';
    signal esp_rx2   : std_logic;
    signal running   : boolean := true;

    signal ultimo    : std_logic_vector(7 downto 0) := (others => '0');
    signal pc_count  : natural := 0;
    signal dig_erros : natural := 0;
begin
    clk <= not clk after T_CLK / 2 when running else '0';

    uut : entity work.BOARD_TOP
        port map (
            CLK           => clk,
            RESET_N       => reset_n,
            KEY1          => key1,
            KEY2          => key2,
            LED           => led,
            DIG           => dig,
            SEG           => seg,
            UART_TXD      => uart_txd,
            UART_RXD      => '1',
            ESP32_TX2     => esp_tx2,
            ESP32_RX2     => esp_rx2,
            DBG_RX_SAMPLE => open,
            DBG_RX_READY  => open,
            DBG_TX_BUSY   => open
        );

    esp32_recebe : process
        variable b : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(esp_rx2);
        wait for T_BIT / 2;
        for i in 0 to 7 loop
            wait for T_BIT;
            b(i) := esp_rx2;
        end loop;
        wait for T_BIT;
        ultimo   <= b;
        pc_count <= pc_count + 1;
    end process;

    confere_display : process
    begin
        wait until rising_edge(clk);
        if reset_n = '1' and dig /= "1110" and dig /= "1101" and dig /= "1011" and dig /= "0111" then
            report "DIG deveria ter exatamente um digito ativo (em '0')" severity error;
            dig_erros <= dig_erros + 1;
        end if;
    end process;

    stim : process
        variable erros : natural := 0;

        procedure confere(ok : boolean; msg : string) is
        begin
            if not ok then
                erros := erros + 1;
                report msg severity error;
            end if;
        end procedure;

        procedure esp32_envia(pacote : bytes_t) is
        begin
            for n in pacote'range loop
                esp_tx2 <= '0';
                wait for T_BIT;
                for i in 0 to 7 loop
                    esp_tx2 <= pacote(n)(i);
                    wait for T_BIT;
                end loop;
                esp_tx2 <= '1';
                wait for T_BIT;
            end loop;
            wait for 15 * T_BIT;
        end procedure;
    begin
        reset_n <= '0';
        wait for 1 us;
        reset_n <= '1';
        wait for 100 us;

        confere(led = "1111", "todos os LEDs deveriam iniciar apagados (ativos em '0')");
        wait until dig = "0111";
        wait until rising_edge(clk);
        confere(seg = "10010010", "digito da esquerda (DIG4) deveria mostrar '5', o nibble alto de TX_BYTE");
        confere(uart_txd = '1' and esp_rx2 = '1', "linhas TX deveriam estar em '1' em repouso");

        esp32_envia((x"23", x"4C", x"B3"));
        confere(led(4) = '0', "pacote de ligar deveria acender o LED4");
        confere(pc_count = 1 and ultimo = x"31", "FPGA deveria responder '1' ao ESP32");

        esp32_envia((x"23", x"44", x"BB"));
        confere(led(4) = '1', "pacote de desligar deveria apagar o LED4");
        confere(pc_count = 2 and ultimo = x"30", "FPGA deveria responder '0' ao ESP32");

        esp32_envia((x"23", x"4C", x"00"));
        confere(led(4) = '1', "checagem errada nao deveria alterar o LED4");
        confere(pc_count = 3 and ultimo = x"45", "FPGA deveria responder 'E' ao ESP32");

        key2 <= '0';
        wait for 10 us;
        confere(led(1) = '0', "KEY2 pressionada deveria acender o LED1 (loopback)");
        key1 <= '0';
        wait for 100 us;
        key1 <= '1';
        wait for 12 * T_BIT;
        key2 <= '1';
        confere(pc_count = 4 and ultimo = x"53", "KEY1 deveria transmitir 'S'");
        confere(<<signal .tb_BOARD_TOP.uut.data_out : std_logic_vector(7 downto 0)>> = x"53",
                "loopback: o RX deveria receber 'S'");

        erros := erros + dig_erros;
        if erros = 0 then
            report "TESTE OK" severity note;
        else
            report "FALHOU: " & integer'image(erros) & " erro(s)" severity error;
        end if;
        running <= false;
        wait;
    end process;
end architecture sim;
