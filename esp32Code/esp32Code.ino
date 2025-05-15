#include <Arduino.h>
#include <NimBLEDevice.h>

// 16-bit UUIDs
#define SERVICE_UUID_16        0x1819
#define CHARACTERISTIC_UUID_16 0x2B1E
#define DEVICE_NAME            "ESP32-LED-Controller"

#define LED_1 2
#define LED_2 4

NimBLECharacteristic* pCharacteristic = nullptr;

// helper to do the actual printing & LED toggling
static void handleIncoming(NimBLECharacteristic* pChr) {
  auto val = pChr->getValue();
  Serial.print("Received [");
  for (size_t i = 0; i < val.size(); i++) {
    Serial.printf(" %02X", (uint8_t)val[i]);
  }
  Serial.println(" ]");
  if (val.size() > 0) {
    uint8_t cmd = (uint8_t)val[0];
    digitalWrite(LED_1, (cmd & 0x01) ? HIGH : LOW);
    digitalWrite(LED_2, (cmd & 0x02) ? HIGH : LOW);
    Serial.printf("Cmd=0x%02X → LED1:%s LED2:%s\n",
      cmd,
      (cmd & 0x01) ? "ON" : "OFF",
      (cmd & 0x02) ? "ON" : "OFF"
    );
  }
}

class MyServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    Serial.println("Client connected");
    digitalWrite(LED_1, HIGH);
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    Serial.println("Client disconnected");
    digitalWrite(LED_1, LOW);
    NimBLEDevice::startAdvertising();
  }
};

class CharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  // ← correct signature: two parameters
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo &ci) override {
    handleIncoming(pChr);
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(LED_1, OUTPUT); digitalWrite(LED_1, LOW);
  pinMode(LED_2, OUTPUT); digitalWrite(LED_2, LOW);

  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  auto* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEUUID svcUUID((uint16_t)SERVICE_UUID_16);
  auto*    pService = pServer->createService(svcUUID);

  NimBLEUUID chrUUID((uint16_t)CHARACTERISTIC_UUID_16);
  pCharacteristic = pService->createCharacteristic(
    chrUUID,
    NIMBLE_PROPERTY::WRITE    /* write with response */ 
  | NIMBLE_PROPERTY::WRITE_NR /* write without response */
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();

  auto* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(svcUUID);
  pAdv->start();
  Serial.println("BLE Advertising with write-char (0x2B1E) ready");
}

void loop() {
  delay(100);
}
