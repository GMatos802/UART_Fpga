# Versão para a placa OMDAZZ / RZ-EasyFPGA

Adaptação do projeto para a placa **OMDAZZ / RZ-EasyFPGA** (Intel Cyclone IV E `EP4CE6E22C8`, 144 pinos), para
testes fora do laboratório. Usa os mesmos módulos da raiz do repositório (`../hw/hdl/`: `UART_TX`, `UART_RX`,
`CMD_EXEC`, `UART_TOP`), o mesmo firmware do ESP32 (`../esp32/`) e a mesma página de teste (`../web/`).

```
placa_omdazz/
├── hdl/
│   ├── BOARD_TOP.vhd      top da placa (é o top no Quartus)
│   └── SEG7_SCAN.vhd      driver do display de 4 dígitos
├── tb/
│   ├── tb_BOARD_TOP.vhd   testbench do top da placa
│   └── run_ghdl.sh        simulação (GHDL)
└── quartus/
    ├── uart_omdazz.qpf    projeto
    ├── uart_omdazz.qsf    dispositivo, arquivos e pinagem
    └── uart_omdazz.sdc    restrição de clock (50 MHz)
```

## 1. Uso

### 1.1 BOARD_TOP

A placa tem só 4 botões e 4 LEDs, então o `BOARD_TOP` adapta o `UART_TOP` (que continua idêntico ao da DE10-Lite):

| Recurso | Na placa |
|---|---|
| Reset | botão **RESET** |
| Enviar byte (`tx_start`) | **KEY1**: envia o byte fixo `TX_BYTE` (padrão `0x53`, 'S') |
| Loopback | **KEY2 mantida pressionada**: RX escuta o próprio TX; solta: RX escuta o ESP32 |
| LED de comando | **LED4** (ligado/desligado pelos pacotes) |
| Indicador de loopback | **LED1** (aceso enquanto KEY2 está pressionada) |
| Display | dígitos 1–2: `TX_BYTE` (o que KEY1 envia); dígitos 3–4: último byte recebido (`data_out`) |
| FPGA → PC | `tx_out` também sai no **USB-serial da placa** (pino 114) |

Generics do `BOARD_TOP` (ajuste em `hdl/BOARD_TOP.vhd` se necessário):

| Generic | Padrão | Função |
|---|---|---|
| `TX_BYTE` | `x"53"` | byte enviado pela KEY1 |
| `RX_FROM_USB` | `false` | `true`: o RX escuta o USB-serial da placa em vez do ESP32 (para testar só com o PC) |
| `LED_ACTIVE_LOW` | `true` | LEDs acendem com `'0'` |
| `SEG_ACTIVE_LOW` / `DIG_ACTIVE_LOW` | `true` | polaridade dos segmentos e dos dígitos do display |

> Se os LEDs ou o display aparecerem invertidos (apagados quando deveriam acender, ou dígitos "fantasmas"),
> troque o generic correspondente para `false`.

### 1.2 Pinagem

| Sinal (BOARD_TOP) | Na placa | Pino |
|---|---|---|
| `CLK` | oscilador 50 MHz | 23 |
| `RESET_N` | botão RESET | 25 |
| `KEY1`, `KEY2` | KEY1, KEY2 | 88, 89 |
| `LED[1..4]` | led1…led4 | 87, 86, 85, 84 |
| `DIG[1..4]` | dígitos do display | 133, 135, 136, 137 |
| `SEG[0..7]` | segmentos a…g, ponto | 128, 121, 125, 129, 132, 126, 124, 127 |
| `UART_TXD` | USB-serial da placa (FPGA → PC) | 114 |
| `UART_RXD` | USB-serial da placa (PC → FPGA) | 115 |
| `ESP32_TX2` | conector do LCD, linha **D0** ← ESP32 GPIO17 | 142 |
| `ESP32_RX2` | conector do LCD, linha **D1** → ESP32 GPIO16 | 1 |
| `DBG_RX_SAMPLE` | conector do LCD, linha **D2** (osciloscópio) | 144 |
| `DBG_RX_READY` | conector do LCD, linha **D3** (osciloscópio) | 3 |
| `DBG_TX_BUSY` | conector do LCD, linha **D4** (osciloscópio) | 2 |

O ESP32 e os sinais de depuração usam o **conector do LCD 1602** (barra fêmea), porque o LCD não é usado e o
conector aceita jumpers. Num LCD 1602 padrão, D0…D4 ficam nas posições **7, 8, 9, 10 e 11** do conector, e GND
na posição **1**; confira na serigrafia da sua placa.

### 1.3 Só a placa

1. Aperte **RESET**.
2. Segure **KEY2** (LED1 acende) e aperte **KEY1**: o 'S' é transmitido, volta pelo loopback e aparece nos
   dígitos 3–4 do display (`53 53`).
3. Para ver no PC: abra um terminal no USB-serial da placa a 9600 8N1 (ex.: `picocom -b 9600 /dev/ttyUSB0`) e
   aperte KEY1: aparece `S`.

### 1.4 Com o ESP32

Ligações (os dois são 3,3 V, ligação direta; **não** ligue o 5 V/VIN do ESP32 na FPGA):

| ESP32 DevKit (30 pinos) | Placa OMDAZZ |
|---|---|
| GPIO17 (TX2) | conector LCD, D0 (pino 142) |
| GPIO16 (RX2) | conector LCD, D1 (pino 1) |
| GND | conector LCD, GND |

1. Grave o firmware: abra `../esp32/` no VS Code com PlatformIO e clique em **Upload**, ou:
   ```bash
   cd ../esp32
   ~/.platformio/penv/bin/pio run -t upload
   ~/.platformio/penv/bin/pio device monitor
   ```
2. O ESP32 cria a rede Wi-Fi **`UART-FPGA`** (senha **`fpga1234`**), com endereço `http://192.168.4.1`.
   Para usar a sua rede, preencha `WIFI_SSID` e `WIFI_PASS` no topo de `../esp32/src/main.cpp`; o IP aparece no
   monitor serial (115200).
3. Conecte o PC na rede do ESP32 e abra **`../web/index.html`** no navegador (duplo clique no arquivo).
4. **Testar conexão** → **Ligar** / **Desligar**: o **LED4** acende/apaga, o display mostra o último byte
   recebido e a página mostra a confirmação do FPGA.

API do ESP32 (todas as respostas em JSON, com CORS liberado):

| Rota | Função |
|---|---|
| `GET /` | verifica se o ESP32 está no ar |
| `POST /led` (`state=on` ou `off`) | envia o pacote e espera a resposta do FPGA (até 100 ms) |
| `POST /send` (`mode=hex` ou `text`, `data`) | envia bytes livres ao FPGA |
| `GET /rx?since=N` | bytes recebidos do FPGA a partir do contador N |

### 1.5 Só com o PC (sem ESP32)

Com `RX_FROM_USB => true` no `BOARD_TOP`, o RX escuta o USB-serial da placa. Os pacotes podem ser enviados do
terminal:

```bash
stty -F /dev/ttyUSB0 9600 cs8 -cstopb -parenb raw
printf '\x23\x4C\xB3' > /dev/ttyUSB0
printf '\x23\x44\xBB' > /dev/ttyUSB0
```

O primeiro acende o LED4 e o segundo apaga; a resposta (`1` / `0`) aparece em um terminal aberto na mesma porta.

---

## 2. Simulação

```bash
./placa_omdazz/tb/run_ghdl.sh
```

Ou com Docker, a partir da raiz do repositório:

```bash
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/w -w /w/placa_omdazz/tb hdlc/ghdl:yosys bash ./run_ghdl.sh
```

O `tb_BOARD_TOP` verifica: pacote de ligar acende o LED4 e o FPGA responde `'1'`; pacote de desligar apaga e
responde `'0'`; checagem errada não altera o LED e responde `'E'`; com KEY2 pressionada, KEY1 envia 'S' e ele
volta pelo loopback; o display tem sempre exatamente um dígito ativo. Resultado esperado: `TESTE OK`.

## 3. Quartus

1. Abra `quartus/uart_omdazz.qpf` no Quartus Prime Lite (com suporte a Cyclone IV instalado).
2. *Processing → Start Compilation*.
3. *Tools → Programmer*: selecione o USB-Blaster e grave `output_files/uart_omdazz.sof`.
4. Teste conforme a seção 1.3.

## 4. Osciloscópio

1. GND da ponta no GND do conector do LCD.
2. Canal 1 em **D1** (`ESP32_RX2` = `tx_out`) ou em **D0** (`ESP32_TX2`, linha que o RX recebe) e canal 2 em
   **D2** (`DBG_RX_SAMPLE`).
3. Trigger na borda de descida do canal 1, base de tempo ~100 µs/div (bit ≈ 104 µs, quadro ≈ 1,04 ms).
4. Em loopback (KEY2 pressionada), mantenha KEY1 pressionada para o quadro se repetir.
5. Para 'S', a linha mostra `0 | 1 1 0 0 1 0 1 0 | 1`, e `DBG_RX_SAMPLE` mostra 8 pulsos, cada um no meio de um
   bit de dados. `DBG_RX_READY` (D3) e `DBG_TX_BUSY` (D4) mostram os pinos de status.

## 5. Fluxo completo (página → ESP32 → FPGA)

1. ESP32 ligado conforme a seção 1.4 (KEY2 solta) e `../web/index.html` aberta.
2. **Ligar**: o log mostra `TX > 23 4C B3` e `FPGA confirmou: LED ligado`; o LED4 acende.
3. **Desligar**: `TX > 23 44 BB`, `LED desligado`; o LED4 apaga.
4. Em *Bytes livres*, envie `23 4C 00` (checagem errada): o log mostra `RX < 45 |E|` e o LED não muda.
5. Aperte KEY1: o 'S' aparece no log como `RX < 53 |S|` (FPGA → ESP32 → página).
