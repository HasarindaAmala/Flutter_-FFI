#include <Arduino.h>
#include <FastLED.h>
#include <NimBLEDevice.h>

// ——————— LED STRIP CONFIG ———————
#define NUM_LEDS    32
#define DATA_PIN    2      // WS2811 data pin
#define BRIGHTNESS  250
CRGB leds[NUM_LEDS];

// ——————— BLE CONFIG ———————
#define SERVICE_UUID_16        0x1819
#define CHARACTERISTIC_UUID_16 0x2B1E
#define DEVICE_NAME            "ESP32-LED-Controller"

NimBLECharacteristic* pCharacteristic = nullptr;

// ── HELPER: immediately turn strip off and show ──
static void stripOff() {
  FastLED.clear();
  FastLED.show();
}

// ── Blink “color” for 100 ms ON, then 100 ms OFF ──
static void blinkColor100ms(const CRGB &color) {
  fill_solid(leds, NUM_LEDS, color);
  FastLED.show();
  delay(100);
  stripOff();
  delay(100);
}

// ── Startup: blink GREEN 3× (100 ms ON / 100 ms OFF) ──
static void blinkStartupGreen() {
  for (int i = 0; i < 3; i++) {
    blinkColor100ms(CRGB::Green);
  }
}

// ── Blink one character in binary, with “char‐start” YELLOW ──
//    1) YELLOW blink 100 ms ON → 100 ms OFF
//    2) For each of 8 bits (MSB→LSB), exactly 100 ms:
//         • if bit == 1 → RED ON 100 ms
//         • if bit == 0 → OFF 100 ms
//
static void blinkCharWithIndicators(uint8_t c) {
  // 1) Character-start indicator: YELLOW ON 100 ms → OFF 100 ms
  blinkColor100ms(CRGB::Yellow);

  // 2) Send 8 bits, MSB first, each bit = 100 ms
  for (int bitIndex = 7; bitIndex >= 0; bitIndex--) {
    bool bitIsOne = ((c >> bitIndex) & 0x01);
    if (bitIsOne) {
      // RED ON for 100 ms
      fill_solid(leds, NUM_LEDS, CRGB::Red);
    } else {
      // OFF for 100 ms
      FastLED.clear();
    }
    FastLED.show();
    delay(100);
  }
}

// ── Blink an entire ASCII string in binary ──
//    1) blinkStartupGreen()  
//    2) for each character, blinkCharWithIndicators()  
//    3) leave strip OFF at end
//
static void blinkStringWithIndicators(const String &input) {
  blinkStartupGreen();

  for (size_t i = 0; i < input.length(); i++) {
    uint8_t asciiCode = static_cast<uint8_t>(input.charAt(i));
    blinkCharWithIndicators(asciiCode);
  }

  stripOff();
}

// ── Existing ControllLed(...) for 6‐byte legacy commands ──
//    mode_: 0=off, 1=solid, 2=blink
//    r,g,b: color components
//    interval: blink interval in ms
//
void ControllLed(uint8_t mode_, uint8_t r, uint8_t g, uint8_t b, uint16_t interval) {
  static bool     blinkState   = false;
  static uint32_t lastToggleMs = 0;

  switch (mode_) {
    case 1: {  // solid
      fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
      FastLED.show();
      break;
    }
    case 2: {  // blink all
      uint32_t now = millis();
      if (now - lastToggleMs >= interval) {
        lastToggleMs = now;
        blinkState   = !blinkState;
        fill_solid(
          leds, NUM_LEDS,
          blinkState ? CRGB(r, g, b) : CRGB::Black
        );
        FastLED.show();
      }
      break;
    }
    default: {  // off / unknown
      FastLED.clear();
      FastLED.show();
      break;
    }
  }
}

// ── BLE Server Callbacks ──
class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    Serial.println("Client connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    Serial.println("Client disconnected, restarting advertising");
    NimBLEDevice::startAdvertising();
  }
};

// ── BLE Characteristic Callbacks ──
//    • If payload length == 6 AND first byte is 0,1, or 2 → legacy command.
//    • Otherwise → treat as UTF-8 text string.
//
class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo&) override {
    auto val = pChr->getValue();  // raw bytes

    // ── Case A: exactly 6 bytes AND val[0] ∈ {0,1,2} → legacy command ──
    if (val.size() == 6) {
      uint8_t possibleMode = (uint8_t)val[0];
      if (possibleMode == 0 || possibleMode == 1 || possibleMode == 2) {
        uint8_t mode_    = possibleMode;
        uint8_t r        = (uint8_t)val[1];
        uint8_t g        = (uint8_t)val[2];
        uint8_t b        = (uint8_t)val[3];
        uint16_t interval = (uint16_t(val[4]) << 8) | uint16_t(val[5]);

        // Call the existing LED routine
        ControllLed(mode_, r, g, b, interval);
        Serial.printf(
          "▶ LEGACY CMD: mode=%u, R=%u, G=%u, B=%u, interval=%u ms\n",
          mode_, r, g, b, interval
        );
        return;
      }
    }

    // ── Case B: otherwise, treat as ASCII text ──
    String incoming = "";
    for (size_t i = 0; i < val.size(); i++) {
      incoming += char(val[i]);
    }
    Serial.print("▶ Received TEXT: ");
    Serial.println(incoming);

    blinkStringWithIndicators(incoming);
  }
};

void setup() {
  Serial.begin(115200);

  // — LED init —
  FastLED.addLeds<WS2811, DATA_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  stripOff();

  // — BLE init —
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEUUID svcUUID((uint16_t)SERVICE_UUID_16);
  NimBLEService* pService = pServer->createService(svcUUID);

  NimBLEUUID chrUUID((uint16_t)CHARACTERISTIC_UUID_16);
  pCharacteristic = pService->createCharacteristic(
    chrUUID,
    NIMBLE_PROPERTY::WRITE |
    NIMBLE_PROPERTY::WRITE_NR
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(svcUUID);
  pAdv->setName(DEVICE_NAME);
  pAdv->start();

  Serial.println("BLE up and advertising (write‐char 0x2B1E)");
}

void loop() {
  // All work happens in onWrite(); nothing needed here.
  delay(100);
}
