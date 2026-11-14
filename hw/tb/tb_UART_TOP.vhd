library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_UART_TOP is
end entity tb_UART_TOP;

architecture sim of tb_UART_TOP is
    constant T_CLK : time := 20 ns;
    constant T_BIT : time := 1 sec / 9600;

    type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant ESPERADO : bytes_t := (
        x"53", x"52",
        x"23", x"4C", x"B3", x"31",
        x"30", x"31", x"45", x"30"
    );

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '0';
    signal tx_start  : std_logic := '1';
    signal data_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal loopback  : std_logic := '1';
    signal rx_ext    : std_logic := '1';
    signal tx_out    : std_logic;
    signal data_out  : std_logic_vector(7 downto 0);
    signal tx_busy   : std_logic;
    signal rx_ready  : std_logic;
    signal rx_sample : std_logic;
    signal led       : std_logic;
    signal running   : boolean := true;

    signal linha_rx    : std_logic;
    signal ready_erros : natural := 0;
    signal recebidos   : bytes_t(0 to 31) := (others => (others => '0'));
    signal pc_count    : natural := 0;
    signal busy_erros  : natural := 0;
    signal t0_quadro   : time := 0 ns;
    signal id_quadro   : natural := 0;
    signal smp_erros   : natural := 0;
begin
    clk <= not clk after T_CLK / 2 when running else '0';

    uut : entity work.UART_TOP
        port map (
            clk       => clk,
            rst       => rst,
            tx_start  => tx_start,
            data_in   => data_in,
            loopback  => loopback,
            rx_ext    => rx_ext,
            tx_out    => tx_out,
            data_out  => data_out,
            tx_busy   => tx_busy,
            rx_ready  => rx_ready,
            rx_sample => rx_sample,
            led       => led
        );

    linha_rx <= tx_out when loopback = '1' else rx_ext;

    confere_ready : process
    begin
        wait until rising_edge(clk);
        if rx_ready = '1' then
            wait until rising_edge(clk);
            if rx_ready /= '0' then
                report "rx_ready deveria durar 1 ciclo" severity error;
                ready_erros <= ready_erros + 1;
            end if;
        end if;
    end process;

    esp32_recebe : process
        variable b : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(tx_out);
        wait for T_BIT / 2;
        for i in 0 to 7 loop
            wait for T_BIT;
            b(i) := tx_out;
        end loop;
        wait for T_BIT;
        assert tx_out = '1' report "stop bit invalido em tx_out" severity error;
        recebidos(pc_count) <= b;
        pc_count <= pc_count + 1;
    end process;

    marca_quadro_rx : process
    begin
        wait until falling_edge(linha_rx);
        t0_quadro <= now;
        id_quadro <= id_quadro + 1;
        wait for 9 * T_BIT + T_BIT / 2;
    end process;

    confere_mid_bit : process
        variable k      : natural := 1;
        variable id     : natural := 0;
        variable ideal  : time;
        variable desvio : time;
    begin
        wait until rising_edge(clk);
        if rx_sample = '1' then
            if id_quadro /= id then
                id := id_quadro;
                k  := 1;
            end if;
            ideal := t0_quadro + k * T_BIT + T_BIT / 2;
            if now > ideal then
                desvio := now - ideal;
            else
                desvio := ideal - now;
            end if;
            if desvio > T_BIT / 16 or k > 8 then
                report "rx_sample " & integer'image(k) & " fora do meio do bit" severity error;
                smp_erros <= smp_erros + 1;
            end if;
            k := k + 1;
        end if;
    end process;

    mede_quadro : process
        variable t0 : time;
    begin
        wait until rising_edge(tx_busy);
        t0 := now;
        wait until falling_edge(tx_busy);
        if now - t0 /= 10 * 5208 * T_CLK then
            report "quadro deveria durar 10 x 5208 ciclos, durou " & time'image(now - t0) severity error;
            busy_erros <= busy_erros + 1;
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

        procedure aperta_botao(b : std_logic_vector(7 downto 0)) is
        begin
            data_in  <= b;
            wait for 10 us;
            tx_start <= '0';
            wait for 100 us;
            tx_start <= '1';
            wait for 12 * T_BIT;
        end procedure;

        procedure esp32_envia(pacote : bytes_t) is
        begin
            for n in pacote'range loop
                rx_ext <= '0';
                wait for T_BIT;
                for i in 0 to 7 loop
                    rx_ext <= pacote(n)(i);
                    wait for T_BIT;
                end loop;
                rx_ext <= '1';
                wait for T_BIT;
            end loop;
            wait for 15 * T_BIT;
        end procedure;
    begin
        rst <= '0';
        wait for 1 us;
        rst <= '1';
        wait for 100 us;

        confere(tx_out = '1', "linha deveria estar em '1' em repouso");
        confere(tx_busy = '0', "tx_busy deveria estar em '0' em repouso");
        confere(led = '0', "LED deveria iniciar apagado");

        loopback <= '1';
        aperta_botao(x"53");
        confere(data_out = x"53", "loopback: data_out deveria ser 0x53 ('S')");
        aperta_botao(x"52");
        confere(data_out = x"52", "loopback: data_out deveria ser 0x52 ('R')");
        data_in <= x"FF";
        wait for 2 * T_BIT;
        confere(pc_count = 2, "mudar as chaves sem apertar o botao nao deveria enviar nada");

        aperta_botao(x"23");
        aperta_botao(x"4C");
        aperta_botao(x"B3");
        wait for 15 * T_BIT;
        confere(led = '1', "loopback: pacote '#' 'L' ~'L' pelo botao deveria acender o LED");

        loopback <= '0';
        wait for 5.3 us;

        esp32_envia((x"23", x"44", x"BB"));
        confere(led = '0', "ESP32: pacote de desligar deveria apagar o LED");

        esp32_envia((x"55", x"23", x"4C", x"B3"));
        confere(led = '1', "ESP32: ruido seguido de pacote de ligar deveria acender o LED");

        esp32_envia((x"23", x"4C", x"00"));
        confere(led = '1', "ESP32: pacote com checagem errada nao deveria alterar o LED");

        esp32_envia((x"23", x"44", x"BB"));
        confere(led = '0', "ESP32: pacote de desligar deveria apagar o LED");

        confere(pc_count = ESPERADO'length,
                "esperava " & integer'image(ESPERADO'length) & " bytes em tx_out, vieram " &
                integer'image(pc_count));
        for i in ESPERADO'range loop
            if i < pc_count then
                confere(recebidos(i) = ESPERADO(i),
                        "byte " & integer'image(i) & " em tx_out: esperava 0x" & to_hstring(ESPERADO(i)) &
                        ", veio 0x" & to_hstring(recebidos(i)));
            end if;
        end loop;

        erros := erros + ready_erros + busy_erros + smp_erros;
        if erros = 0 then
            report "TESTE OK" severity note;
        else
            report "FALHOU: " & integer'image(erros) & " erro(s)" severity error;
        end if;
        running <= false;
        wait;
    end process;
end architecture sim;
