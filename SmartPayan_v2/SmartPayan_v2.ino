/*
  SmartPayan v3 — Final Integrated Firmware
  Features:
  - Auto + Manual Mode
  - Slider: 0=retract, 0.5=auto, 1=extend
  - Sends clotheslineState to RTDB
  - Reads commands from RTDB
  - Optimized light mapping (lux → 0..1000)
  - Clean debug mode
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>

// ----- CONFIG -----
const char* WIFI_SSID = "Isonoe";
const char* WIFI_PASSWORD = "Ang$arapne22";

const char* firebaseURL =
  "https://smartpayan-f7ea7-default-rtdb.asia-southeast1.firebasedatabase.app/devices/";

bool DEBUG_MODE = true;

// ----- PINS -----
#define DHT_PIN 4
#define DHT_TYPE DHT22
#define RAIN_ANALOG_PIN 34
#define RAIN_DIGITAL_PIN 35
#define MOTOR_IN1 25
#define MOTOR_IN2 26
#define MOTOR_ENA 27
#define I2C_SDA 21
#define I2C_SCL 22

// ----- CONSTANTS -----
int RAIN_THRESHOLD = 2500;
int LIGHT_THRESHOLD = 100;      // lux threshold for night
int SENSOR_READ_INTERVAL = 5000;
int DATA_UPDATE_INTERVAL = 10000;
int COMMAND_READ_INTERVAL = 1000;

int MOTOR_SPEED = 80;

// ----- OBJECTS -----
DHT dht(DHT_PIN, DHT_TYPE);
BH1750 lightMeter;

enum ClotheslineState { EXTENDED, RETRACTED, MOVING };
ClotheslineState currentState = RETRACTED;

bool autoMode = true;
float sliderValue = 0.5;

float temperature = 0;
float humidity = 0;
float luxRaw = 0;
float lightLevel = 0;   // mapped 0..1000
int rainAnalog = 4095;
int rainDigital = HIGH;
bool rainDetected = false;

// Firebase Keys
String realMac = "";
String deviceKey = "";

// timers
unsigned long lastSensorRead = 0;
unsigned long lastDataUpdate = 0;
unsigned long lastCommandRead = 0;

void setup() {
  Serial.begin(115200);
  Serial.println("\nSmartPayan v3 Starting...");

  pinMode(RAIN_ANALOG_PIN, INPUT);
  pinMode(RAIN_DIGITAL_PIN, INPUT);
  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  pinMode(MOTOR_ENA, OUTPUT);

  dht.begin();
  Wire.begin(I2C_SDA, I2C_SCL);

  if (!lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE))
    Serial.println("BH1750 init failed");

  // WiFi
  Serial.print("Connecting WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) { delay(300); Serial.print("."); }
  Serial.println("\nConnected");

  realMac = WiFi.macAddress();
  deviceKey = realMac; deviceKey.replace(":", "_");

  Serial.println("MAC: " + realMac);
  Serial.println("DeviceKey: " + deviceKey);
}

// ------------------------ LOOP ------------------------
void loop() {
  unsigned long ms = millis();

  if (ms - lastSensorRead >= SENSOR_READ_INTERVAL) {
    lastSensorRead = ms;
    readSensors();
    if (DEBUG_MODE) printDebug();
  }

  if (ms - lastCommandRead >= COMMAND_READ_INTERVAL) {
    lastCommandRead = ms;
    readCommandsFromFirebase();
  }

  if (ms - lastDataUpdate >= DATA_UPDATE_INTERVAL) {
    lastDataUpdate = ms;
    sendToFirebase();
  }

  if (autoMode) automaticDecision();

  delay(10);
}

// ------------------------ SENSOR READ ------------------------
void readSensors() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t)) temperature = t;
  if (!isnan(h)) humidity = h;

  float lux = lightMeter.readLightLevel();
  if (lux >= 0) luxRaw = lux;

  float capped = min((float)50000, luxRaw);
  lightLevel = capped / 50.0;  // 0–1000

  rainAnalog = analogRead(RAIN_ANALOG_PIN);
  rainDigital = digitalRead(RAIN_DIGITAL_PIN);

  bool analogWet = rainAnalog < RAIN_THRESHOLD;
  bool digitalWet = (rainDigital == LOW);

  rainDetected = analogWet || digitalWet;
}

// ------------------------ DEBUG PRINT ------------------------
void printDebug() {
  Serial.println("---- Sensor Debug ----");
  Serial.printf("Temp: %.1f\n", temperature);
  Serial.printf("Humidity: %.1f\n", humidity);
  Serial.printf("Light raw(lux): %.1f\n", luxRaw);
  Serial.printf("Light mapped: %.1f\n", lightLevel);
  Serial.printf("RainAnalog: %d\n", rainAnalog);
  Serial.printf("RainDigital: %d\n", rainDigital);
  Serial.printf("RainDetected: %s\n", rainDetected ? "YES" : "NO");
  Serial.printf("AutoMode: %s\n", autoMode ? "true" : "false");
  Serial.printf("SliderValue: %.2f\n", sliderValue);
  Serial.printf("State: %s\n", getStateString(currentState).c_str());
  Serial.println("------------------------\n");
}

// ------------------------ FIREBASE COMMAND READER ------------------------
void readCommandsFromFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/commands.json";

  HTTPClient http;
  http.begin(url);
  int code = http.GET();

  if (code <= 0) { http.end(); return; }

  String payload = http.getString();
  http.end();

  if (payload.indexOf("autoMode") != -1) {
    autoMode = payload.indexOf("\"autoMode\":true") != -1;
  }

  if (payload.indexOf("clotheslinePosition") != -1) {
    int start = payload.indexOf("clotheslinePosition") + 21;
    int end = payload.indexOf(",", start);
    sliderValue = payload.substring(start, end).toFloat();
  }

  if (!autoMode) {
    if (sliderValue == 0) retract();
    else if (sliderValue == 1) extend();
  }
}

// ------------------------ AUTO LOGIC ------------------------
void automaticDecision() {
  bool retractNow = false;
  bool extendNow = false;

  if (rainDetected) retractNow = true;
  else if (lightLevel < 200) retractNow = true;  // night
  else if (humidity > 85) retractNow = true;
  else extendNow = true;

  if (retractNow && currentState != RETRACTED) retract();
  if (extendNow && currentState != EXTENDED) extend();
}

// ------------------------ MOTOR CONTROL ------------------------
void extend() {
  currentState = MOVING;
  digitalWrite(MOTOR_IN1, HIGH);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, MOTOR_SPEED);
  delay(1000);
  stopMotor();
  currentState = EXTENDED;
  sendStateToFirebase();
}

void retract() {
  currentState = MOVING;
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, HIGH);
  analogWrite(MOTOR_ENA, MOTOR_SPEED);
  delay(1000);
  stopMotor();
  currentState = RETRACTED;
  sendStateToFirebase();
}

void stopMotor() {
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, 0);
}

// ------------------------ FIREBASE UPLOAD ------------------------
void sendToFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/sensorData.json";

  String json = "{";
  json += "\"macAddress\":\"" + realMac + "\",";
  json += "\"temperature\":" + String(temperature, 1) + ",";
  json += "\"humidity\":" + String(humidity, 1) + ",";
  json += "\"lightLevel\":" + String(lightLevel, 1) + ",";
  json += "\"rain\":" + String(rainDetected ? "true" : "false") + ",";
  json += "\"state\":\"" + getStateString(currentState) + "\"";
  json += "}";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.PUT(json);
  http.end();
}

void sendStateToFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  String json = "\"" + getStateString(currentState) + "\"";
  http.PUT(json);

  http.end();
}

// ------------------------ STATE STRING ------------------------
String getStateString(ClotheslineState state) {
  switch (state) {
    case EXTENDED: return "extended";
    case RETRACTED: return "retracted";
    case MOVING: return "moving";
    default: return "unknown";
  }
}
