#include <Arduino.h>
#include <FastLED.h>
#include <NimBLEDevice.h>

// —————— LED STRIP CONFIG ——————
#define NUM_LEDS    32
#define DATA_PIN    2
#define BRIGHTNESS  200
CRGB leds[NUM_LEDS];

// —————— BLE CONFIG ——————
#define SERVICE_UUID_16        0x1819
#define CHARACTERISTIC_UUID_16 0x2B1E
#define DEVICE_NAME            "ESP32-LED-Controller"
NimBLECharacteristic* pCharacteristic = nullptr;

// —————— GLOBAL STATE ——————
uint8_t  gMode           = 0;      // 0=off, 1=solid, 2=blink all, 3=blink single
uint8_t  gR              = 0;
uint8_t  gG              = 0;
uint8_t  gB              = 0;
uint16_t interval        = 0;      // blink interval (ms)
uint8_t  idx             = 0;      // single-LED index for mode 3

bool     gBlinkState     = false;
uint32_t gLastToggleMs   = 0;

// —————— LED CONTROL ——————
void ControllLed(uint8_t mode_, uint8_t r, uint8_t g, uint8_t b, uint16_t interval) {
  switch(mode_) {
    case 1: // solid
      fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
      FastLED.show();
      break;

    case 2: { // blink all
      uint32_t now = millis();
      if (now - gLastToggleMs >= interval) {
        gLastToggleMs = now;
        gBlinkState   = !gBlinkState;
        fill_solid(leds, NUM_LEDS,
                   gBlinkState ? CRGB(r, g, b) : CRGB::Black);
        FastLED.show();
      }
      break;
    }

    default: // off
      FastLED.clear();
      FastLED.show();
      break;
  }
}

void ControllSingleLed(uint8_t /*mode*/, uint8_t r, uint8_t g, uint8_t b, uint16_t interval, uint8_t bulbIdx) {
  if (bulbIdx >= NUM_LEDS) return;
  uint32_t now = millis();
  if (now - gLastToggleMs >= interval) {
    gLastToggleMs = now;
    gBlinkState   = !gBlinkState;
    leds[bulbIdx] = gBlinkState ? CRGB(r, g, b) : CRGB::Black;
    FastLED.show();
  }
}

// —————— BLE CALLBACKS ——————
class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    Serial.println("Client connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    Serial.println("Client disconnected, restarting advertising");
    NimBLEDevice::startAdvertising();
  }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo&) override {
    auto val = pChr->getValue();
    if (val.size() == 6) {
      gMode    = val[0];
      gR       = val[1];
      gG       = val[2];
      gB       = val[3];
      interval = (uint16_t(val[4]) << 8) | uint16_t(val[5]);
      Serial.printf("▶ Cmd: mode=%u R=%u G=%u B=%u interval=%ums\n",
                    gMode, gR, gG, gB, interval);
    }
    else if (val.size() >= 7) {
      gMode    = val[0];
      gR       = val[1];
      gG       = val[2];
      gB       = val[3];
      interval = (uint16_t(val[4]) << 8) | uint16_t(val[5]);
      idx      = val[6];
      Serial.printf("▶ Cmd: mode=%u R=%u G=%u B=%u interval=%ums idx=%u\n",
                    gMode, gR, gG, gB, interval, idx);
    }
    else {
      Serial.printf("⚠️ Invalid packet (%u bytes)\n", val.size());
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
  switch (gMode) {
    case 2:
      ControllLed(gMode, gR, gG, gB, interval);
      break;
    case 3:
      ControllSingleLed(gMode, gR, gG, gB, interval, idx);
      break;
    case 1:
      // draw solid once, then lock to avoid constant redraw
      ControllLed(gMode, gR, gG, gB, interval);
      gMode = 255;
      break;
    default:
      FastLED.clear();
      FastLED.show();
      break;
  }
  delay(10);
}
