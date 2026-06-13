#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// motor pin — GPIO 8 on ESP32 C3 MINI
#define MOTOR_PIN 8

// BLE service and characteristic UUIDs
#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

// connection callbacks
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Device connected");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Device disconnected — restarting advertising");
    BLEDevice::startAdvertising();
  }
};

// haptic patterns
void fireH1() {
  // minor correction — 1 pulse 80ms
  digitalWrite(MOTOR_PIN, HIGH);
  delay(80);
  digitalWrite(MOTOR_PIN, LOW);
}

void fireH2() {
  // major error — 2 pulses 40ms each
  digitalWrite(MOTOR_PIN, HIGH);
  delay(40);
  digitalWrite(MOTOR_PIN, LOW);
  delay(60);
  digitalWrite(MOTOR_PIN, HIGH);
  delay(40);
  digitalWrite(MOTOR_PIN, LOW);
}

void fireH3() {
  // success — smooth ramp up and down using PWM
  for (int i = 0; i <= 255; i += 5) {
    analogWrite(MOTOR_PIN, i);
    delay(4);
  }
  delay(100);
  for (int i = 255; i >= 0; i -= 5) {
    analogWrite(MOTOR_PIN, i);
    delay(4);
  }
}

// characteristic write callback — fires when app sends H1/H2/H3
class CharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    Serial.print("Received: ");
    Serial.println(value);

    if (value == "H1") {
        fireH1();
        Serial.print("Received: ");
        Serial.println(value);

    } else if (value == "H2") {
      fireH2();
    } else if (value == "H3") {
      fireH3();
    }
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(MOTOR_PIN, OUTPUT);
  digitalWrite(MOTOR_PIN, LOW);

  // init BLE
  BLEDevice::init("SmartPen");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // create service and characteristic
  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());

  // start service and advertising
  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("SmartPen BLE ready — waiting for connection");
}

void loop() {
  // nothing needed here — all handled by callbacks
  delay(1000);
}
