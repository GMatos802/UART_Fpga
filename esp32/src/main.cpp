#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>

static const char *WIFI_SSID = "";
static const char *WIFI_PASS = "";

static const char *AP_SSID = "UART-FPGA";
static const char *AP_PASS = "fpga1234";

static const uint32_t FPGA_BAUD = 9600;
static const int FPGA_RX_PIN = 16;
static const int FPGA_TX_PIN = 17;

static const uint8_t PKT_START = 0x23;
static const uint8_t CMD_LED_ON = 0x4C;
static const uint8_t CMD_LED_OFF = 0x44;
static const uint8_t RESP_ON = 0x31;
static const uint8_t RESP_OFF = 0x30;
static const uint8_t RESP_ERR = 0x45;
static const uint32_t RESP_TIMEOUT_MS = 100;

static const size_t RX_BUF_SIZE = 1024;
static const size_t MAX_SEND = 256;

WebServer server(80);

static uint8_t rxBuf[RX_BUF_SIZE];
static uint32_t rxTotal = 0;
static uint32_t txTotal = 0;

static void pumpRx() {
  while (Serial2.available()) {
    uint8_t b = (uint8_t)Serial2.read();
    rxBuf[rxTotal % RX_BUF_SIZE] = b;
    rxTotal++;
    Serial.printf("RX <- FPGA: 0x%02X '%c'\n", b, (b >= 32 && b < 127) ? b : '.');
  }
}

static void sendToFpga(const uint8_t *data, size_t n) {
  Serial2.write(data, n);
  Serial2.flush();
  txTotal += n;
  Serial.printf("TX -> FPGA:");
  for (size_t i = 0; i < n; i++) Serial.printf(" %02X", data[i]);
  Serial.println();
}

static String bytesJson(const uint8_t *b, size_t n) {
  String s = "[";
  for (size_t i = 0; i < n; i++) {
    if (i) s += ",";
    s += String(b[i]);
  }
  return s + "]";
}

static void reply(int code, const String &json) {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.send(code, "application/json", json);
}

static void replyError(int code, String msg) {
  msg.replace("\\", "/");
  msg.replace("\"", "'");
  reply(code, "{\"ok\":false,\"error\":\"" + msg + "\"}");
}

static bool parseHex(const String &in, uint8_t *out, size_t &n, String &err) {
  n = 0;
  String tok;
  String s = in + " ";
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (c == ' ' || c == ',' || c == '\n' || c == '\t') {
      if (tok.length() == 0) continue;
      if (tok.startsWith("0x") || tok.startsWith("0X")) tok = tok.substring(2);
      bool valid = tok.length() >= 1 && tok.length() <= 2;
      for (size_t k = 0; valid && k < tok.length(); k++) valid = isxdigit((unsigned char)tok[k]);
      if (!valid) {
        err = "byte invalido: " + tok;
        return false;
      }
      if (n >= MAX_SEND) {
        err = "maximo de " + String(MAX_SEND) + " bytes";
        return false;
      }
      out[n++] = (uint8_t)strtoul(tok.c_str(), nullptr, 16);
      tok = "";
    } else {
      tok += c;
    }
  }
  return true;
}

static void handleRoot() {
  reply(200, "{\"ok\":true,\"device\":\"UART-FPGA\",\"rx\":" + String(rxTotal) + ",\"tx\":" + String(txTotal) + "}");
}

static void handleLed() {
  String state = server.arg("state");
  uint8_t cmd;
  if (state == "on") {
    cmd = CMD_LED_ON;
  } else if (state == "off") {
    cmd = CMD_LED_OFF;
  } else {
    replyError(400, "use state=on ou state=off");
    return;
  }

  uint8_t pkt[3] = {PKT_START, cmd, (uint8_t)~cmd};
  pumpRx();
  uint32_t before = rxTotal;
  sendToFpga(pkt, sizeof(pkt));

  uint32_t t0 = millis();
  while (rxTotal == before && millis() - t0 < RESP_TIMEOUT_MS) {
    pumpRx();
    delay(1);
  }

  if (rxTotal == before) {
    reply(504, "{\"ok\":false,\"error\":\"FPGA nao respondeu\",\"sent\":" + bytesJson(pkt, 3) + "}");
    return;
  }

  uint8_t resp = rxBuf[(rxTotal - 1) % RX_BUF_SIZE];
  String led = resp == RESP_ON ? "on" : resp == RESP_OFF ? "off" : "?";
  bool ok = (cmd == CMD_LED_ON && resp == RESP_ON) || (cmd == CMD_LED_OFF && resp == RESP_OFF);
  reply(ok ? 200 : 502, String("{\"ok\":") + (ok ? "true" : "false") + ",\"led\":\"" + led +
                            "\",\"resp\":" + String(resp) + ",\"sent\":" + bytesJson(pkt, 3) + "}");
}

static void handleSend() {
  if (!server.hasArg("data")) {
    replyError(400, "faltou o campo data");
    return;
  }
  String data = server.arg("data");
  String mode = server.hasArg("mode") ? server.arg("mode") : "text";
  uint8_t out[MAX_SEND];
  size_t n = 0;

  if (mode == "hex") {
    String err;
    if (!parseHex(data, out, n, err)) {
      replyError(400, err);
      return;
    }
  } else {
    if (data.length() > MAX_SEND) {
      replyError(400, "maximo de " + String(MAX_SEND) + " bytes");
      return;
    }
    n = data.length();
    memcpy(out, data.c_str(), n);
  }

  if (n == 0) {
    replyError(400, "nada para enviar");
    return;
  }

  sendToFpga(out, n);
  reply(200, "{\"ok\":true,\"sent\":" + bytesJson(out, n) + "}");
}

static void handleRx() {
  uint32_t since = server.hasArg("since") ? strtoul(server.arg("since").c_str(), nullptr, 10) : 0;
  if (since > rxTotal) since = rxTotal;
  if (rxTotal - since > RX_BUF_SIZE) since = rxTotal - RX_BUF_SIZE;

  String s = "{\"ok\":true,\"total\":" + String(rxTotal) + ",\"tx\":" + String(txTotal) + ",\"bytes\":[";
  for (uint32_t i = since; i < rxTotal; i++) {
    if (i != since) s += ",";
    s += String(rxBuf[i % RX_BUF_SIZE]);
  }
  s += "]}";
  reply(200, s);
}

static void startWifi() {
  if (strlen(WIFI_SSID) > 0) {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.printf("Conectando em %s", WIFI_SSID);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) {
      delay(250);
      Serial.print(".");
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("Conectado. Endereco: http://%s\n", WiFi.localIP().toString().c_str());
      return;
    }
    Serial.println("Falhou, criando rede propria.");
  }
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.printf("Rede \"%s\" (senha %s). Endereco: http://%s\n", AP_SSID, AP_PASS,
                WiFi.softAPIP().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(FPGA_BAUD, SERIAL_8N1, FPGA_RX_PIN, FPGA_TX_PIN);
  delay(200);
  while (Serial2.available()) Serial2.read();

  startWifi();

  server.on("/", HTTP_GET, handleRoot);
  server.on("/led", HTTP_POST, handleLed);
  server.on("/send", HTTP_POST, handleSend);
  server.on("/rx", HTTP_GET, handleRx);
  server.onNotFound([]() {
    if (server.method() == HTTP_OPTIONS) {
      reply(204, "");
    } else {
      replyError(404, "rota inexistente");
    }
  });
  server.begin();
}

void loop() {
  server.handleClient();
  pumpRx();
}
