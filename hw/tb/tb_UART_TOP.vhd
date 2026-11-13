library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_UART_TOP is
end entity tb_UART_TOP;

architecture sim of tb_UART_TOP is
    constant T_CLK : time := 20 ns;
    constant T_BIT : time := 1 sec / 9600;

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '0';
    signal tx_start : std_logic := '1';
    signal data_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_out   : std_logic;
    signal data_out : std_logic_vector(7 downto 0);
    signal tx_busy  : std_logic;
    signal rx_ready  : std_logic;
    signal rx_sample : std_logic;
    signal running   : boolean := true;

    signal ready_count : natural := 0;
    signal ready_erros : natural := 0;
    signal pc_byte     : std_logic_vector(7 downto 0) := (others => '0');
    signal pc_count    : natural := 0;
    signal busy_erros  : natural := 0;
    signal t0_quadro   : time := 0 ns;
    signal id_quadro   : natural := 0;
    signal smp_erros   : natural := 0;
begin
    clk <= not clk after T_CLK / 2 when running else '0';

    uut : entity work.UART_TOP
        port map (
            clk      => clk,
            rst      => rst,
            tx_start => tx_start,
            data_in  => data_in,
            tx_out   => tx_out,
            data_out => data_out,
            tx_busy   => tx_busy,
            rx_ready  => rx_ready,
            rx_sample => rx_sample
        );

    conta_ready : process
    begin
        wait until rising_edge(clk);
        if rx_ready = '1' then
            ready_count <= ready_count + 1;
            wait until rising_edge(clk);
            if rx_ready /= '0' then
                report "rx_ready deveria durar 1 ciclo" severity error;
                ready_erros <= ready_erros + 1;
            end if;
        end if;
    end process;

    osciloscopio : process
        variable b : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(tx_out);
        t0_quadro <= now;
        id_quadro <= id_quadro + 1;
        wait for T_BIT / 2;
        for i in 0 to 7 loop
            wait for T_BIT;
            b(i) := tx_out;
        end loop;
        wait for T_BIT;
        assert tx_out = '1' report "stop bit invalido em tx_out" severity error;
        pc_byte  <= b;
        pc_count <= pc_count + 1;
    end process;

    confere_mid_bit : process
        variable k       : natural := 1;
        variable id      : natural := 0;
        variable ideal   : time;
        variable desvio  : time;
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
    begin
        rst <= '0';
        wait for 1 us;
        rst <= '1';
        wait for 100 us;

        confere(tx_out = '1', "linha deveria estar em '1' em repouso");
        confere(tx_busy = '0', "tx_busy deveria estar em '0' em repouso");

        aperta_botao(x"53");
        confere(ready_count = 1, "esperava 1 pulso de rx_ready apos 'S'");
        confere(data_out = x"53", "data_out deveria ser 0x53 ('S')");
        confere(pc_count = 1 and pc_byte = x"53", "tx_out deveria transmitir 'S'");

        aperta_botao(x"52");
        confere(ready_count = 2, "esperava 2 pulsos de rx_ready apos 'R'");
        confere(data_out = x"52", "data_out deveria ser 0x52 ('R')");
        confere(pc_count = 2 and pc_byte = x"52", "tx_out deveria transmitir 'R'");

        data_in <= x"FF";
        wait for 2 * T_BIT;
        confere(data_out = x"52", "mudar as chaves sem apertar o botao nao deveria enviar nada");
        confere(pc_count = 2, "nenhum quadro deveria ser enviado sem apertar o botao");

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
