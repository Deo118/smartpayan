/*
  SmartPayan v4 — Full RTDB Sync (fixed)
  - Auto + Manual w/ slider
  - Motor actions synced both ways
  - ESP reads/writes state
  - Prevents override conflicts
  - Clean bidirectional logic
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>

// --- CONFIG ---
const char* WIFI_SSID = "Isonoe";
const char* WIFI_PASSWORD = "Ang$arapne22";

const char* firebaseURL =
  "https://smartpayan-f7ea7-default-rtdb.asia-southeast1.firebasedatabase.app/devices/";

bool DEBUG_MODE = true;

// --- PINS ---
#define DHT_PIN 4
#define DHT_TYPE DHT22
#define RAIN_ANALOG_PIN 34
#define RAIN_DIGITAL_PIN 35
#define MOTOR_IN1 25
#define MOTOR_IN2 26
#define MOTOR_ENA 27
#define I2C_SDA 21
#define I2C_SCL 22

// --- CONSTANTS ---
int RAIN_THRESHOLD = 2500;
int LIGHT_THRESHOLD = 100;
int SENSOR_READ_INTERVAL = 5000;
int COMMAND_READ_INTERVAL = 1000;
int DATA_UPDATE_INTERVAL = 10000;

int MOTOR_SPEED = 80;

// --- OBJECTS ---
DHT dht(DHT_PIN, DHT_TYPE);
BH1750 lightMeter;

enum ClotheslineState { EXTENDED, RETRACTED, MOVING };
ClotheslineState currentState = RETRACTED;
ClotheslineState rtdbState = RETRACTED;

bool autoMode = true;
float sliderValue = 0.5;

float temperature = 0;
float humidity = 0;
float luxRaw = 0;
float lightLevel = 0;
bool rainDetected = false;

// Firebase keys
String realMac;
String deviceKey;

// timers
unsigned long lastSensorRead = 0;
unsigned long lastDataUpdate = 0;
unsigned long lastCommandRead = 0;

// -------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("\nSmartPayan v4 Ready...");

  pinMode(RAIN_ANALOG_PIN, INPUT);
  pinMode(RAIN_DIGITAL_PIN, INPUT);
  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  pinMode(MOTOR_ENA, OUTPUT);

  dht.begin();
  Wire.begin(I2C_SDA, I2C_SCL);
  if (!lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE)) {
    Serial.println("Warning: BH1750 init failed");
  }

  Serial.print("Connecting WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) { Serial.print("."); delay(200); }

  realMac = WiFi.macAddress();            // e.g. AA:BB:CC:DD:EE:FF
  deviceKey = realMac;
  deviceKey.replace(":", "_");            // e.g. AA_BB_CC_DD_EE_FF

  Serial.println("\nConnected as:");
  Serial.println(deviceKey);
}

// -------------------------------------------------------
void loop() {
  unsigned long ms = millis();

  if (ms - lastSensorRead >= SENSOR_READ_INTERVAL) {
    lastSensorRead = ms;
    readSensors();
    if (DEBUG_MODE) printDebug();
  }

  if (ms - lastCommandRead >= COMMAND_READ_INTERVAL) {
    lastCommandRead = ms;
    readCommands();    // kept name simple to match loop()
    readRTDBState();   // sync state from app
  }

  if (ms - lastDataUpdate >= DATA_UPDATE_INTERVAL) {
    lastDataUpdate = ms;
    sendSensorData();
  }

  applyControlLogic();

  delay(10);
}

// -------------------------------------------------------
void readSensors() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();

  if (!isnan(t)) temperature = t;
  if (!isnan(h)) humidity = h;

  float lux = lightMeter.readLightLevel();
  if (lux >= 0) luxRaw = lux;

  lightLevel = min((float)50000, luxRaw) / 50.0; // mapped 0..1000

  int analog = analogRead(RAIN_ANALOG_PIN);
  int digital = digitalRead(RAIN_DIGITAL_PIN);

  rainDetected = (analog < RAIN_THRESHOLD) || (digital == LOW);
}

// -------------------------------------------------------
void readCommands() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/commands.json";

  HTTPClient http;
  http.begin(url);
  int code = http.GET();

  if (code <= 0) { http.end(); return; }

  String payload = http.getString();
  http.end();

  // --- AUTO MODE ---
  if (payload.indexOf("\"autoMode\":") != -1) {
    autoMode = payload.indexOf("\"autoMode\":true") != -1;
  }

  // --- SLIDER (clotheslinePosition) ---
  int pos = payload.indexOf("clotheslinePosition");
  if (pos != -1) {
    int colon = payload.indexOf(":", pos);
    if (colon != -1) {
      int comma = payload.indexOf(",", colon);
      int endIdx = (comma == -1) ? payload.indexOf("}", colon) : comma;
      if (endIdx != -1 && endIdx > colon) {
        String numStr = payload.substring(colon + 1, endIdx);
        numStr.trim();
        sliderValue = numStr.toFloat();
      }
    }
  }

  // --- APPLY USER COMMANDS (interpretation)
  if (!autoMode) {
    if (sliderValue <= 0.1) {          // Treat ~0.0 as RETRACT
      retract();
    } 
    else if (sliderValue >= 0.9) {     // Treat ~1.0 as EXTEND
      extend();
    } 
    else {                             // 0.5 (or other mid) => go back to auto
      autoMode = true;
    }
  }
}

// -------------------------------------------------------
void readRTDBState() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  int code = http.GET();
  if (code <= 0) { http.end(); return; }

  String state = http.getString();
  http.end();

  if (state.indexOf("extended") != -1) rtdbState = EXTENDED;
  else if (state.indexOf("retracted") != -1) rtdbState = RETRACTED;
  // if RTDB says moving or unknown, we ignore/change nothing

  // If app changed state manually, ESP follows (only when NOT auto)
  if (rtdbState != currentState && !autoMode) {
    if (rtdbState == EXTENDED) extend();
    if (rtdbState == RETRACTED) retract();
  }
}

// -------------------------------------------------------
void applyControlLogic() {
  if (!autoMode) return;

  bool retractNow = false;
  bool extendNow = false;

  if (rainDetected) retractNow = true;
  else if (lightLevel < 200) retractNow = true;
  else if (humidity > 85) retractNow = true;
  else extendNow = true;

  if (retractNow && currentState != RETRACTED) retract();
  if (extendNow && currentState != EXTENDED) extend();
}

// -------------------------------------------------------
void extend() {
  currentState = MOVING;
  digitalWrite(MOTOR_IN1, HIGH);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, MOTOR_SPEED); // If analogWrite unavailable on your core, switch to ledc
  delay(1000);
  stopMotor();
  currentState = EXTENDED;
  updateState();
}

void retract() {
  currentState = MOVING;
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, HIGH);
  analogWrite(MOTOR_ENA, MOTOR_SPEED);
  delay(1000);
  stopMotor();
  currentState = RETRACTED;
  updateState();
}

void stopMotor() {
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  analogWrite(MOTOR_ENA, 0);
}

// -------------------------------------------------------
void updateState() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseURL) + deviceKey + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.PUT("\"" + getStateString(currentState) + "\"");
  http.end();
}

// -------------------------------------------------------
void sendSensorData() {
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

// -------------------------------------------------------
String getStateString(ClotheslineState s) {
  if (s == EXTENDED) return "extended";
  if (s == RETRACTED) return "retracted";
  return "moving";
}

// -------------------------------------------------------
void printDebug() {
  Serial.println("---- SmartPayan Debug ----");
  Serial.printf("AutoMode: %s\n", autoMode ? "true" : "false");
  Serial.printf("Slider: %.2f\n", sliderValue);
  Serial.printf("State: %s\n", getStateString(currentState).c_str());
  Serial.printf("RTDB State: %s\n", getStateString(rtdbState).c_str());
  Serial.printf("Temp: %.1f\n", temperature);
  Serial.printf("Humidity: %.1f\n", humidity);
  Serial.printf("Light: %.1f (mapped: 0-1000)\n", lightLevel);
  Serial.printf("Rain: %s\n", rainDetected ? "YES" : "NO");
  Serial.println("--------------------------\n");
}
