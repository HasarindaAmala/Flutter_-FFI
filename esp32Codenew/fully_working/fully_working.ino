#include <Arduino.h>
#include <FastLED.h>
#include <NimBLEDevice.h>

#define NUM_LEDS    32
#define DATA_PIN    2
#define BRIGHTNESS  150

CRGB leds[NUM_LEDS];

#define SERVICE_UUID_16        0x1819
#define CHARACTERISTIC_UUID_16 0x2B1E
#define DEVICE_NAME            "ESP32-LED-Controller"

NimBLECharacteristic* pCharacteristic = nullptr;

static bool     blinkState   = false;
static uint32_t lastToggleMs = 0;

uint8_t  gMode     = 0;
uint8_t  gR        = 0;
uint8_t  gG        = 0;
uint8_t  gB        = 0;
uint16_t gInterval = 99;

bool ledOn = false;

enum BlinkState {
  BS_IDLE,
  BS_START_MARKER,
  BS_MARKER_ON,
  BS_MARKER_OFF,
  BS_BIT_ON,
  BS_BIT_OFF
};

static BlinkState    textState      = BS_IDLE;
static unsigned long phaseStart     = 0;
static int           startupStep    = 0;
static int           charIndex      = 0;
static int           bitIndex       = 0;
static int           prevBitValue   = -1;  // New: Track previous bit
static String        currentMessage = "";
static bool          newMessageFlag = false;
int markerIndex = 0;  // 0–5 (111000)
bool bitIsOn = false;

static void stripOff() {
  FastLED.clear();
  FastLED.show();
}

static void blinkColor200ms(const CRGB &color) {
  fill_solid(leds, NUM_LEDS, color);
  FastLED.show();
  delay(gInterval);
  stripOff();
  delay(gInterval);
}
const uint8_t blinkIndices[] = {10,11, 12,13,18,19,21, 20,2,3,4,5,26,27,28,29};
const uint8_t numToBlink = sizeof(blinkIndices) / sizeof(blinkIndices[0]);

void ControllLed(uint8_t mode_, uint8_t r, uint8_t g, uint8_t b, uint16_t interval) {
  switch (mode_) {
    case 1:
      fill_solid(leds, NUM_LEDS, CRGB(r, g, b));
      FastLED.show();
      break;
    case 2: {
      uint32_t now = millis();
      if (now - lastToggleMs >= interval) {
        lastToggleMs = now;
        blinkState = !blinkState;
        fill_solid(leds, NUM_LEDS, CRGB::Black);
       if (blinkState) {
    for (int i = 0; i < numToBlink; i++) {
      leds[blinkIndices[i]] = CRGB(r, g, b);  // Use your desired color
    }
  }
        FastLED.show();
      }
      break;
    }
    default:
      stripOff();
      break;
  }
}

static void blinkStartupGreen() {
  for (int i = 0; i < 3; i++) {
    blinkColor200ms(CRGB::Green);
  }
}

static void processTextState() {
  unsigned long now = millis();

  switch (textState) {
    case BS_IDLE:
      if (newMessageFlag) {
        newMessageFlag = false;
        charIndex = 0;
        markerIndex = 0;
        bitIndex = 7;
        ledOn = false;
        textState = BS_START_MARKER;
        phaseStart = now;
      }
      break;

    case BS_START_MARKER:
      if (now - phaseStart >= gInterval) {
        phaseStart = now;

        if (ledOn) {
          stripOff();
        } else {
          fill_solid(leds, NUM_LEDS, markerIndex < 3 ? CRGB::Red : CRGB::Blue);
          FastLED.show();
        }

        ledOn = !ledOn;

        if (!ledOn) {
          markerIndex++;
          if (markerIndex >= 6) {
            markerIndex = 0;
            bitIndex = 7;
            textState = BS_BIT_ON;
          }
        }
      }
      break;

    case BS_BIT_ON:
      if (now - phaseStart >= gInterval) {
        phaseStart = now;

        if (bitIndex >= 0) {
          if (ledOn) {
            stripOff();
            ledOn = false;
            bitIndex--;
          } else {
            char c = currentMessage.charAt(charIndex);
            bool bit = (c >> bitIndex) & 0x01;
            fill_solid(leds, NUM_LEDS, bit ? CRGB::Red : CRGB::Blue);
            FastLED.show();
            ledOn = true;
          }
        } else {
          stripOff();
          textState = BS_IDLE;

          // Prepare for repeat if more characters
          charIndex++;
          if (charIndex < currentMessage.length()) {
            textState = BS_START_MARKER;
            markerIndex = 0;
            bitIndex = 7;
            ledOn = false;
            phaseStart = now;
          } else {
             textState = BS_START_MARKER;
charIndex = 0;
bitIndex = 7;
markerIndex = 0;
ledOn = false;
phaseStart = now;
          }
        }
      }
      break;

    default:
      break;
  }
}

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
    uint8_t possibleMode = static_cast<uint8_t>(val[0]);
    if (possibleMode <= 2) {
      gMode = possibleMode;
      gR = static_cast<uint8_t>(val[1]);
      gG = static_cast<uint8_t>(val[2]);
      gB = static_cast<uint8_t>(val[3]);
      gInterval = (static_cast<uint16_t>(val[4]) << 8) | static_cast<uint16_t>(val[5]);
      if (gInterval < 20) gInterval = 99;

      // 🛑 Stop any active text transmission
      currentMessage = "";
      newMessageFlag = false;
      textState = BS_IDLE;
      stripOff();

      Serial.printf("\u25B6 LEGACY CMD: mode=%u, R=%u, G=%u, B=%u, interval=%u ms\n", gMode, gR, gG, gB, gInterval);
      return;
    }
  }

  // 🟢 Valid text message
  String incoming = "";
  for (size_t i = 0; i < val.size(); i++) incoming += char(val[i]);

  Serial.print("\u25B6 Received TEXT: ");
  Serial.println(incoming);

  currentMessage = incoming;
  gMode = 0;
textState = BS_IDLE;
charIndex = 0;
bitIndex = 7;
markerIndex = 0;
ledOn = false;
lastToggleMs = millis();
newMessageFlag = true;
stripOff();             // <--- Ensure all LEDs are off
phaseStart = millis();
if (gInterval < 20) gInterval = 99;// <--- Proper sync with clock
 // Reset state machine
}
};

void setup() {
  Serial.begin(115200);
  FastLED.addLeds<WS2811, DATA_PIN, GRB>(leds, NUM_LEDS);
  FastLED.setBrightness(BRIGHTNESS);
  stripOff();

  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  NimBLEServer* pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  NimBLEUUID svcUUID((uint16_t)SERVICE_UUID_16);
  NimBLEService* pService = pServer->createService(svcUUID);

  NimBLEUUID chrUUID((uint16_t)CHARACTERISTIC_UUID_16);
  pCharacteristic = pService->createCharacteristic(
    chrUUID,
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());

  pService->start();
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(svcUUID);
  pAdv->setName(DEVICE_NAME);
  pAdv->start();

  Serial.println("BLE up and advertising (write-char 0x2B1E)");
}

void loop() {
  if (currentMessage.length() > 0 || textState != BS_IDLE) {
    processTextState();
  }
  else if (gMode > 0) {
    ControllLed(gMode, gR, gG, gB, gInterval);
  }
  else {
    static bool wasOn = true;
    if (wasOn) {
      stripOff();   // turn off only once
      wasOn = false;
    }
  }

  yield();  // instead of delay
}
