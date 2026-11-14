# UART em VHDL — DE10-Lite

Projeto final de Laboratório de Sistemas Digitais. Implementação de uma interface UART (transmissor e receptor)
em VHDL para a placa **Terasic DE10-Lite** (FPGA Intel MAX 10 `10M50DAF484C7G`), com modo **loopback interno** e
integração com um **ESP32**: uma página web envia comandos via Wi-Fi ao ESP32, que os repassa por UART ao FPGA
(por enquanto: ligar e desligar o LEDR9).

```
[Página web] --Wi-Fi/HTTP--> [ESP32] --UART 9600 8N1--> [FPGA]
             <-------------         <------------------
```

| Parâmetro | Valor |
|---|---|
| Clock do sistema | 50 MHz |
| Baud rate | 9600 bps |
| Quadro | 8N1 (8 bits de dados, sem paridade, 1 stop bit), LSB primeiro, linha ociosa em `'1'` |
| Recepção | oversampling de 16×, amostragem no meio do bit (mid-bit) |

---

## 1. O que foi feito

- **UART_TX**: transmissor serial com FSM Moore (controle) e datapath separados.
- **UART_RX**: receptor serial com FSM Moore e datapath separados, gerador de tick de oversampling e
  sincronizador de entrada.
- **CMD_EXEC**: executor de comandos (FSM Moore + datapath) que interpreta pacotes recebidos pelo RX, liga ou
  desliga o LED e responde pelo TX.
- **UART_TOP**: top-level puramente estrutural que instancia TX, RX e CMD_EXEC; a chave SW9 escolhe entre
  loopback interno (TX → RX) e recepção externa (ESP32 → RX).
- **Firmware do ESP32** (`esp32/`): API HTTP via Wi-Fi que encaminha bytes ao FPGA por UART.
- **Página de teste** (`web/index.html`): liga/desliga o LED e mostra todo o tráfego.
- **Testbench** autoverificável que envia e recebe dois caracteres distintos ('S' e 'R').
- **Projeto Quartus** com pinagem completa da DE10-Lite e restrição de clock.

As FSMs seguem as HLFSMs Moore do grupo (`docs/HLFSM_UART_moore.drawio`).

---

## 2. Estrutura do repositório

```
hw/
├── hdl/
│   ├── UART_TX.vhd        transmissor
│   ├── UART_RX.vhd        receptor
│   ├── CMD_EXEC.vhd       executor de comandos (LED)
│   └── UART_TOP.vhd       top-level
├── tb/
│   ├── tb_UART_TOP.vhd    testbench
│   └── run_ghdl.sh        script de simulação (GHDL)
└── quartus/
    ├── uart_de10.qpf      projeto
    ├── uart_de10.qsf      dispositivo, arquivos e pinagem
    └── uart_de10.sdc      restrição de clock (50 MHz)
esp32/
├── platformio.ini         projeto PlatformIO (placa esp32dev)
└── src/main.cpp           firmware: Wi-Fi + API HTTP + UART2
web/
└── index.html             página de teste (abrir no navegador)
placa_omdazz/              versão para a placa OMDAZZ / RZ-EasyFPGA (ver placa_omdazz/README.md)
docs/                      diagramas e material para o relatório
```

---

## 3. O código

Cada módulo (TX e RX) está em um único arquivo, com o **bloco de controle** e o **bloco de dados** em processos
separados:

| Processo | Bloco | Função |
|---|---|---|
| `ctrl_state` | Controle | registrador de estado |
| `ctrl_next` | Controle | lógica de próximo estado (usa só sinais de status) |
| `ctrl_out` | Controle | sinais de controle, função só do estado (Moore) |
| `dp_regs` | Datapath | contadores, shift register e registradores |

### 3.1 Cálculo dos divisores

```
N_TX = 50 000 000 / 9600         ≈ 5208 ciclos por bit
N_RX = 50 000 000 / (9600 × 16)  ≈ 326 ciclos por tick (16 ticks por bit)
```

Os dois valores são calculados a partir dos generics `CLK_FREQ`, `BAUD` e `OVERSAMPLE`.

### 3.2 UART_TX

Portas: `clk`, `rst`, `tx_start`, `data_in(7:0)`, `tx_out`, `tx_busy`.

| Registrador | Largura | Função |
|---|---|---|
| `state` | 3 bits | estado da FSM |
| `cnt` | 13 bits | contador de baud (até 5207) |
| `bit_cnt` | 3 bits | contador de bits de dados (0 a 7) |
| `sr` | 8 bits | shift register com o byte a enviar |
| `start_sync` | 2 bits | sincronizador do `tx_start` (botão assíncrono) |

| Estado | `tx_out` | `tx_busy` | Ações | Saída |
|---|---|---|---|---|
| IDLE | `1` | `0` | `cnt := 0`, `bit_cnt := 0`, `sr := data_in` | `tx_start` → START |
| START | `0` | `1` | `cnt := cnt + 1` | `cnt = 5206` → START_END |
| START_END | `0` | `1` | `cnt := 0` | → DATA |
| DATA | `sr(0)` | `1` | `cnt := cnt + 1` | `cnt = 5206` → SHIFT |
| SHIFT | `sr(0)` | `1` | `cnt := 0`, desloca `sr`, `bit_cnt := bit_cnt + 1` | `bit_cnt = 7` → STOP, senão DATA |
| STOP | `1` | `1` | `cnt := cnt + 1` | `cnt = 5207` → IDLE |

Temporização: start = 5207 + 1, cada dado = 5207 + 1, stop = 5208 ciclos → **5208 ciclos por bit**.

### 3.3 UART_RX

Portas: `clk`, `rst`, `rx_in`, `data_out(7:0)`, `rx_ready` e a saída de depuração `rx_sample`.

| Registrador | Largura | Função |
|---|---|---|
| `state` | 4 bits | estado da FSM |
| `tick_cnt` | 9 bits | gerador de tick (0 a 325) |
| `s_cnt` | 4 bits | contador de amostragem (0 a 15) |
| `bit_cnt` | 3 bits | contador de bits de dados (0 a 7) |
| `sr` | 8 bits | shift register com os bits recebidos |
| `dout` | 8 bits | byte recebido, ligado a `data_out` |
| `sync` | 2 bits | sincronizador do `rx_in` |

| Estado | `rx_ready` | Ações | Saída |
|---|---|---|---|
| IDLE | `0` | `s_cnt := 0`, `bit_cnt := 0` | `rx_in = 0` → START |
| START | `0` | `s_cnt` avança a cada tick | 8º tick: `rx_in = 0` → START_OK; `rx_in = 1` (ruído) → IDLE |
| START_OK | `0` | `s_cnt := 0` | → DATA |
| DATA | `0` | `s_cnt` avança a cada tick | 16º tick → SAMPLE |
| SAMPLE | `0` | `sr := rx_in & sr(7..1)`, `s_cnt := 0`, `bit_cnt := bit_cnt + 1` | `bit_cnt = 7` → STOP, senão DATA |
| STOP | `0` | `s_cnt` avança a cada tick | 16º tick: `rx_in = 1` → LOAD; `rx_in = 0` (erro de quadro) → IDLE |
| LOAD | `0` | `dout := sr` | → DONE |
| DONE | `1` | — | → IDLE |

- O start é confirmado no **8º tick** após a borda de descida (meio do start bit); cada bit de dados é amostrado
  **16 ticks** depois do anterior (meio do bit).
- `data_out` só muda em LOAD: não mostra os bits chegando durante a recepção.
- `rx_ready` vale `1` só em DONE: pulso de exatamente 1 ciclo, já com `data_out` válido.
- `rx_sample` pulsa (1 ciclo) em cada amostragem de bit de dados, para visualização no osciloscópio.

### 3.4 CMD_EXEC (comandos)

Protocolo de **pacote de 3 bytes**: início `'#'` (0x23) + comando + checagem (complemento bit a bit do comando).

| Pacote | Ação | Resposta do FPGA (pelo TX) |
|---|---|---|
| `23 4C B3` (`#` `L` ~`L`) | liga o LEDR9 | `31` (`'1'`) |
| `23 44 BB` (`#` `D` ~`D`) | desliga o LEDR9 | `30` (`'0'`) |
| checagem errada ou comando desconhecido | nada | `45` (`'E'`) |

Bytes fora de um pacote (sem o `'#'` inicial) são ignorados.

| Estado | Ações | Saída |
|---|---|---|
| IDLE | — | `rx_ready` e byte = `'#'` → WAIT_CMD |
| WAIT_CMD | — | `rx_ready` → SAVE_CMD |
| SAVE_CMD | `cmd := data_out` | → WAIT_CHK |
| WAIT_CHK | — | `rx_ready`: checagem ok e `cmd = 'L'` → LED_ON; ok e `cmd = 'D'` → LED_OFF; senão → CMD_ERR |
| LED_ON | `led := 1`, `resp := '1'` | → WAIT_TX |
| LED_OFF | `led := 0`, `resp := '0'` | → WAIT_TX |
| CMD_ERR | `resp := 'E'` | → WAIT_TX |
| WAIT_TX | — | `tx_busy = 0` → SEND |
| SEND | `ack_start = 1`, `ack_sel = 1` (TX envia `resp`) | `tx_busy = 1` → IDLE |

O CMD_EXEC também faz a seleção do que o TX transmite: o botão KEY1 envia o byte das chaves e, durante SEND, o
TX envia a resposta.

### 3.5 UART_TOP

Sem FSM e sem registradores: instancia `UART_TX`, `UART_RX` e `CMD_EXEC`, inverte `rst` e `tx_start` (botões
ativos em `'0'`) e escolhe a entrada do RX: `rx_in = tx_out` com `loopback = 1` (SW9) ou `rx_in = rx_ext`
(vindo do ESP32) com `loopback = 0`.

---

## 4. Como usar na placa

| Sinal | Na placa | Pino FPGA |
|---|---|---|
| `clk` | oscilador 50 MHz | `PIN_P11` |
| `rst` | **KEY0** | `PIN_B8` |
| `tx_start` | **KEY1** | `PIN_A7` |
| `data_in(7:0)` | **SW7…SW0** | `C10 C11 D12 C12 A12 B12 A13 A14` (SW0…SW7) |
| `loopback` | **SW9** (1 = loopback, 0 = ESP32) | `PIN_F15` |
| `data_out(7:0)` | **LEDR7…LEDR0** | `A8 A9 A10 B10 D13 C13 E14 D14` (LEDR0…LEDR7) |
| `tx_busy` | **LEDR8** | `PIN_A11` |
| `led` | **LEDR9** (LED de comando) | `PIN_B11` |
| `tx_out` | **JP1 pino 1** (GPIO[0]) → ESP32 GPIO16 | `PIN_V10` |
| `rx_ext` | **JP1 pino 2** (GPIO[1]) ← ESP32 GPIO17 | `PIN_W10` (pull-up) |
| `rx_sample` | **JP1 pino 4** (GPIO[3]) | `PIN_W9` |
| `rx_ready` | **JP1 pino 5** (GPIO[4]) | `PIN_V8` |
| GND | **JP1 pino 12** ↔ GND do ESP32 | — |

### 4.1 Só a placa (loopback, SW9 = 1)

1. Aperte **KEY0** para resetar.
2. Coloque nas chaves **SW7…SW0** o byte a enviar (ex.: `01010011` = 'S') e aperte **KEY1**: o byte é
   transmitido, volta pelo loopback e aparece em **LEDR7…LEDR0**.
3. Para testar o comando sem ESP32, envie o pacote pelo botão, um byte por vez: `00100011` (`#`), `01001100`
   (`L`), `10110011` (~`L`) → **LEDR9 acende**. Para apagar: `00100011`, `01000100`, `10111011`.

Enquanto KEY1 estiver pressionado, o byte é reenviado continuamente (~1 ms por quadro).

### 4.2 Com o ESP32 (SW9 = 0)

Ligações (os dois são 3,3 V, ligação direta; **não** ligue o 5 V/VIN do ESP32 na FPGA):

| ESP32 DevKit (30 pinos) | DE10-Lite (JP1) |
|---|---|
| GPIO17 (TX2) | pino 2 (`rx_ext`) |
| GPIO16 (RX2) | pino 1 (`tx_out`) |
| GND | pino 12 |

1. Grave o firmware: abra `esp32/` no VS Code com PlatformIO e clique em **Upload**, ou:
   ```bash
   cd esp32
   ~/.platformio/penv/bin/pio run -t upload
   ~/.platformio/penv/bin/pio device monitor
   ```
2. O ESP32 cria a rede Wi-Fi **`UART-FPGA`** (senha **`fpga1234`**), com endereço `http://192.168.4.1`.
   Para usar a sua rede, preencha `WIFI_SSID` e `WIFI_PASS` no topo de `esp32/src/main.cpp`; o IP aparece no
   monitor serial (115200).
3. Conecte o PC na rede do ESP32 e abra **`web/index.html`** no navegador (duplo clique no arquivo).
4. **Testar conexão** → **Ligar** / **Desligar**: o LEDR9 acende/apaga e a página mostra a confirmação do FPGA.

API do ESP32 (todas as respostas em JSON, com CORS liberado):

| Rota | Função |
|---|---|
| `GET /` | verifica se o ESP32 está no ar |
| `POST /led` (`state=on` ou `off`) | envia o pacote e espera a resposta do FPGA (até 100 ms) |
| `POST /send` (`mode=hex` ou `text`, `data`) | envia bytes livres ao FPGA |
| `GET /rx?since=N` | bytes recebidos do FPGA a partir do contador N |

Observações:

- `tx_busy` (LEDR8) fica aceso só ~1 ms por quadro; `rx_ready` dura 20 ns e por isso vai para o JP1, onde pode
  ser medido no osciloscópio.

---

## 5. Como testar

### 5.1 Simulação (GHDL)

Com o GHDL instalado (Arch: `yay -S ghdl-mcode`):

```bash
./hw/tb/run_ghdl.sh
```

Ou com Docker, a partir da raiz do repositório:

```bash
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/w -w /w/hw/tb hdlc/ghdl:yosys bash ./run_ghdl.sh
```

Resultado esperado: uma linha com **`TESTE OK`** (avisos `metavalue detected` em 0 ms são normais, ocorrem antes
do reset).

O testbench (`tb_UART_TOP`) verifica automaticamente:

- **loopback**: 'S' (0x53) e 'R' (0x52) enviados pelo botão chegam em `data_out`; mudar as chaves sem apertar o
  botão não transmite nada; o pacote `# L ~L` enviado pelo botão acende o LED;
- **ESP32** (modelo gerando quadros em `rx_ext`): pacote de desligar apaga o LED; byte de ruído seguido de
  pacote de ligar acende; pacote com checagem errada não altera o LED; resposta `'1'`, `'0'` ou `'E'` em `tx_out`
  para cada pacote;
- a sequência exata de todos os bytes transmitidos em `tx_out`;
- `rx_ready` dura exatamente 1 ciclo; cada quadro dura exatamente 10 × 5208 ciclos (`tx_busy`);
- cada pulso de `rx_sample` cai no meio do bit (± 1/16 do período).

### 5.2 Formas de onda

A simulação gera `hw/tb/build/tb_UART_TOP.ghw`. Para abrir:

```bash
gtkwave hw/tb/build/tb_UART_TOP.ghw
```

Sinais úteis:

- topo: `tx_start`, `data_in`, `loopback`, `rx_ext`, `tx_out`, `tx_busy`, `rx_ready`, `rx_sample`, `data_out`, `led`;
- `uut/u_cmd`: `state`, `cmd`, `resp`, `led_q`;
- `uut/u_tx`: `state`, `cnt`, `bit_cnt`, `sr`;
- `uut/u_rx`: `state`, `tick`, `s_cnt`, `bit_cnt`, `sr`.

Para comprovar a amostragem mid-bit, dê zoom em um quadro: cada pulso de `rx_sample` cai no meio de um bit de
`tx_out`.

### 5.3 Na placa (Quartus)

1. Abra `hw/quartus/uart_de10.qpf` no Quartus Prime Lite.
2. *Processing → Start Compilation*.
3. *Tools → Programmer*: selecione o USB-Blaster e grave `output_files/uart_de10.sof`.
4. Teste com os LEDs conforme a seção 4 (ex.: 'S' = `01010011`, 'R' = `01010010`).

### 5.4 Osciloscópio

1. GND da ponta no **JP1 pino 12**.
2. Canal 1 no **pino 1** (`tx_out`) e canal 2 no **pino 4** (`rx_sample`).
3. Trigger na borda de descida do canal 1, base de tempo ~100 µs/div (bit ≈ 104 µs, quadro ≈ 1,04 ms).
4. Mantenha KEY1 pressionado para o quadro se repetir e a imagem ficar estável.
5. Para 'S', `tx_out` mostra `0 | 1 1 0 0 1 0 1 0 | 1`, e `rx_sample` mostra 8 pulsos, cada um no meio de um bit
   de dados.

### 5.5 Fluxo completo (página → ESP32 → FPGA)

1. SW9 = 0, ESP32 ligado conforme a seção 4.2 e `web/index.html` aberta.
2. **Ligar**: o log mostra `TX > 23 4C B3` e `FPGA confirmou: LED ligado`; o LEDR9 acende.
3. **Desligar**: `TX > 23 44 BB`, `LED desligado`; o LEDR9 apaga.
4. Em *Bytes livres*, envie `23 4C 00` (checagem errada): o log mostra `RX < 45 |E|` e o LED não muda.
5. Coloque um caractere nas chaves e aperte KEY1: ele aparece no log como `RX <` (FPGA → ESP32 → página).
