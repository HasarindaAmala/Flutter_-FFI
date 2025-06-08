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

// globals used by ControllLed()
bool     gBlinkState   = false;
uint32_t gLastToggleMs = 0;

// Blink interval is now 16-bit:
uint16_t gInterval     = 500;    // default 500 ms

// BLE characteristic pointer
NimBLECharacteristic* pCharacteristic = nullptr;

// —————— GLOBAL STATE ——————
uint8_t  gMode     = 0;    // 0=off, 1=solid, 2=blink
uint8_t  gR        = 0;    // red value
uint8_t  gG        = 0;    // green value
uint8_t  gB        = 0;    // blue value
uint16_t interval = 0.0;
uint8_t  idx        = 0;// blink interval in ms

bool     gBlinkState   = false;
uint32_t gLastToggleMs = 0;

// ——————— FUNCTION TO CONTROL LEDS ———————
void ControllLed(uint8_t mode_, uint8_t r, uint8_t g, uint8_t b, uint16_t interval) {
  switch (mode_) {
    case 1: { // solid
      fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
      FastLED.show();
      break;
    }
    case 2: { // blink all
      uint32_t now = millis();
      if (now - gLastToggleMs >= interval) {
        gLastToggleMs = now;
        gBlinkState   = !gBlinkState;
        fill_solid(
          leds, NUM_LEDS,
          gBlinkState ? CRGB(r, g, b) : CRGB::Black
        );
        FastLED.show();
      }
      break;
    }
    default: { // off / unknown
      FastLED.clear();
      FastLED.show();
      break;
    }
  }
}

// ——————— BLE SERVER CALLBACKS ———————
class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    Serial.println("Client connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    Serial.println("Client disconnected, restarting advertising");
    NimBLEDevice::startAdvertising();
  }
};

// ——————— CHARACTERISTIC CALLBACKS ———————
class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo&) override {
    auto val = pChr->getValue();
    // Now expect exactly 6 bytes: mode, R, G, B, interval_hi, interval_lo
    if (val.size() == 6) {
      uint8_t  mode_    = val[0];
      uint8_t  r        = val[1];
      uint8_t  g        = val[2];
      uint8_t  b        = val[3];
      gInterval         = (uint16_t(val[4]) << 8) | uint16_t(val[5]);

      // Apply and log
      ControllLed(mode_, r, g, b, gInterval);
      Serial.printf(
        "CMD ▶ mode=%u  R=%u G=%u B=%u  interval=%ums\n",
        mode_, r, g, b, gInterval
      );
    } else {
      Serial.printf("⚠️ Invalid payload length (%u bytes)\n", val.size());
    }
  }
};

void setup() {
  Serial.begin(115200);

  // — LED init —
  FastLED.addLeds<WS2811, DATA_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  FastLED.clear();
  FastLED.show();

  // — BLE init —
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  // Create server + service + characteristic
  auto* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEUUID svcUUID((uint16_t)SERVICE_UUID_16);
  auto*     pService = pServer->createService(svcUUID);

  NimBLEUUID chrUUID((uint16_t)CHARACTERISTIC_UUID_16);
  pCharacteristic = pService->createCharacteristic(
    chrUUID,
    NIMBLE_PROPERTY::WRITE    |
    NIMBLE_PROPERTY::WRITE_NR
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();

   auto* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(svcUUID);
  //pAdv->setScanResponse(true);      // include the NAME in scan-response
  pAdv->setName(DEVICE_NAME);       // advertise as “ESP32-LED-Controller”
  pAdv->start();

  Serial.println("BLE up and advertising (write-char 0x2B1E)");
}

void loop() {
  // Nothing to do here, all handled in onWrite callback
  delay(100);
}
