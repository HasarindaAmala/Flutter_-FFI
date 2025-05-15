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

// BLE characteristic pointer
NimBLECharacteristic* pCharacteristic = nullptr;

// ——————— FUNCTION TO CONTROL LEDS ———————
void ControllLed(uint8_t mode_, uint8_t r, uint8_t g, uint8_t b, uint8_t interval) {
  switch (mode_) {
    case 1: { // solid
      fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
      FastLED.show();
      break;
    }
    case 2: { // blink
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
    Serial.println("Client disconnected");
    NimBLEDevice::startAdvertising();
  }
};

// ——————— CHARACTERISTIC CALLBACKS ———————
class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo&) override {
    auto val = pChr->getValue();
    // Expecting exactly 5 bytes: mode, R, G, B, interval
    if (val.size() >= 5) {
      uint8_t mode_    = val[0];
      uint8_t r        = val[1];
      uint8_t g        = val[2];
      uint8_t b        = val[3];
      uint8_t interval = val[4];

      // Apply the command
      ControllLed(mode_, r, g, b, interval);

      // And log it
      Serial.printf(
        "CMD ▶ mode=%u  R=%u G=%u B=%u  intvl=%ums\n",
        mode_, r, g, b, interval
      );
    } else {
      Serial.println("⚠️ Invalid payload length");
    }
  }

};



void setup() {
  Serial.begin(115200);

  FastLED.addLeds<WS2811, DATA_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  FastLED.clear(); FastLED.show();

  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  auto* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEUUID svcUUID((uint16_t)SERVICE_UUID_16);
  auto*     pService = pServer->createService(svcUUID);

  NimBLEUUID chrUUID((uint16_t)CHARACTERISTIC_UUID_16);
  pCharacteristic = pService->createCharacteristic(
    chrUUID,
    NIMBLE_PROPERTY::WRITE    | NIMBLE_PROPERTY::WRITE_NR
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(svcUUID);
  pAdv->start();

  Serial.println("BLE up and advertising (write-char 0x2B1E)");
}

void loop() {
  delay(100);
}
