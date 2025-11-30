/*
  SmartPayan v4 — Full RTDB Sync (fixed) + Event Rain + Sensitive Light
  - Auto + Manual w/ slider (0 or 1 only, no 0.5)
  - Motor actions synced both ways
  - ESP reads/writes state
  - Prevents override conflicts
  - Clean bidirectional logic
  - Event-based rain detection (immediate send on rain)
  - Increased BH1750 sensitivity (0-1000 range, more responsive)
  - All identifiers in camelCase
  - Offline detection moved to app-side (no device timestamps)
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>

// --- CONFIG ---
const char* wifiSsidVal = "PLDTHOMEFIBRGcfn2";
const char* wifiPasswordVal = "PLDTWIFIDizon12162404";

const char* firebaseUrlVal =
  "https://smartpayan-f7ea7-default-rtdb.asia-southeast1.firebasedatabase.app/devices/";

bool debugModeVal = true;

// --- PINS ---
#define dhtPinVal 4
#define dhtTypeVal DHT22
#define rainAnalogPinVal 34
#define rainDigitalPinVal 35
#define motorIn1Val 25
#define motorIn2Val 26
#define motorEnaVal 27
#define i2cSdaVal 21
#define i2cSclVal 22

// --- CONSTANTS ---
int rainThresholdVal = 2500;
int lightThresholdVal = 100;
int sensorReadIntervalVal = 5000;
int commandReadIntervalVal = 1000;
int dataUpdateIntervalVal = 10000;

int motorSpeedVal = 80;

// --- OBJECTS ---
DHT dhtVal(dhtPinVal, dhtTypeVal);
BH1750 lightMeterVal;

enum ClotheslineStateVal { Extended, Retracted, Moving };
ClotheslineStateVal currentStateVal = Retracted;
ClotheslineStateVal rtdbStateVal = Retracted;

bool autoModeVal = true;
float sliderValueVal = 0.5;

float tempVal = 0;
float humidityVal = 0;
float luxRawVal = 0;
float lightLevelVal = 0;
bool rainDetectedVal = false;
bool lastRainStateVal = false;  

// Firebase keys
String realMacVal;
String deviceKeyVal;

// timers
unsigned long lastSensorReadVal = 0;
unsigned long lastDataUpdateVal = 0;
unsigned long lastCommandReadVal = 0;

// -------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("\nSmartPayan v4 Ready...");

  pinMode(rainAnalogPinVal, INPUT);
  pinMode(rainDigitalPinVal, INPUT);
  pinMode(motorIn1Val, OUTPUT);
  pinMode(motorIn2Val, OUTPUT);
  pinMode(motorEnaVal, OUTPUT);

  dhtVal.begin();
  Wire.begin(i2cSdaVal, i2cSclVal);
  if (!lightMeterVal.begin(BH1750::CONTINUOUS_HIGH_RES_MODE)) {
    Serial.println("Warning: BH1750 init failed");
  }

  Serial.print("Connecting WiFi");
  WiFi.begin(wifiSsidVal, wifiPasswordVal);
  while (WiFi.status() != WL_CONNECTED) { Serial.print("."); delay(200); }

  realMacVal = WiFi.macAddress();            // e.g. AA:BB:CC:DD:EE:FF
  deviceKeyVal = realMacVal;
  deviceKeyVal.replace(":", "_");            // e.g. AA_BB_CC_DD_EE_FF

  Serial.println("\nConnected as:");
  Serial.println(deviceKeyVal);
}

// -------------------------------------------------------
void loop() {
  unsigned long ms = millis();

  if (ms - lastSensorReadVal >= sensorReadIntervalVal) {
    lastSensorReadVal = ms;
    readSensorVals();
    if (debugModeVal) printDebugVal();
  }

  if (ms - lastCommandReadVal >= commandReadIntervalVal) {
    lastCommandReadVal = ms;
    readCommandsVal();    
    readRtdbStateVal();   
  }

  if (ms - lastDataUpdateVal >= dataUpdateIntervalVal) {
    lastDataUpdateVal = ms;
    sendSensorDataVal();
  }

  applyControlLogicVal();

  delay(10);
}

// -------------------------------------------------------
void readSensorVals() {
  float t = dhtVal.readTemperature();
  float h = dhtVal.readHumidity();

  if (!isnan(t)) tempVal = t;
  if (!isnan(h)) humidityVal = h;

  float lux = lightMeterVal.readLightLevel();
  if (lux >= 0) luxRawVal = lux;

  // Increased sensitivity - cap at 10,000 lux, divide by 10 for 0-1000 range
  lightLevelVal = min((float)10000, luxRawVal) / 10.0;

  int analog = analogRead(rainAnalogPinVal);
  int digital = digitalRead(rainDigitalPinVal);

  bool prevRain = rainDetectedVal;
  rainDetectedVal = (analog < rainThresholdVal) || (digital == LOW);

  // Event-based rain detection - send immediately if rain newly detected
  if (rainDetectedVal && !prevRain) {
    Serial.println("Rain detected! Sending data immediately...");
    sendSensorDataVal();
  }
}

// -------------------------------------------------------
void readCommandsVal() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseUrlVal) + deviceKeyVal + "/commands.json";

  HTTPClient http;
  http.begin(url);
  int code = http.GET();

  if (code <= 0) { http.end(); return; }

  String payload = http.getString();
  http.end();

  // --- AUTO MODE ---
  if (payload.indexOf("\"autoMode\":") != -1) {
    autoModeVal = payload.indexOf("\"autoMode\":true") != -1;
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
        sliderValueVal = numStr.toFloat();
      }
    }
  }

  // --- APPLY USER COMMANDS (app) ---
  if (!autoModeVal) {
    if (sliderValueVal <= 0.1) {          // 0: Retract
      retractVal();
    } 
    else if (sliderValueVal >= 0.9) {     // 1: Extend
      extendVal();
    }
  }
}

// -------------------------------------------------------
void readRtdbStateVal() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseUrlVal) + deviceKeyVal + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  int code = http.GET();
  if (code <= 0) { http.end(); return; }

  String state = http.getString();
  http.end();

  if (state.indexOf("extended") != -1) rtdbStateVal = Extended;
  else if (state.indexOf("retracted") != -1) rtdbStateVal = Retracted;
  // if RTDB says moving or unknown, we ignore/change nothing

  // If app changed state manually, ESP follows (only when NOT auto)
  if (rtdbStateVal != currentStateVal && !autoModeVal) {
    if (rtdbStateVal == Extended) extendVal();
    if (rtdbStateVal == Retracted) retractVal();
  }
}

// -------------------------------------------------------
void applyControlLogicVal() {
  if (!autoModeVal) return;

  bool retractNow = false;
  bool extendNow = false;

  if (rainDetectedVal) retractNow = true;
  else if (lightLevelVal < 200) retractNow = true;
  else if (humidityVal > 85) retractNow = true;
  else extendNow = true;

  if (retractNow && currentStateVal != Retracted) retractVal();
  if (extendNow && currentStateVal != Extended) extendVal();
}

// -------------------------------------------------------
void extendVal() {
  currentStateVal = Moving;
  digitalWrite(motorIn1Val, HIGH);
  digitalWrite(motorIn2Val, LOW);
  analogWrite(motorEnaVal, motorSpeedVal); 
  delay(1000);
  stopMotorVal();
  currentStateVal = Extended;
  updateStateVal();
}

void retractVal() {
  currentStateVal = Moving;
  digitalWrite(motorIn1Val, LOW);
  digitalWrite(motorIn2Val, HIGH);
  analogWrite(motorEnaVal, motorSpeedVal);
  delay(1000);
  stopMotorVal();
  currentStateVal = Retracted;
  updateStateVal();
}

void stopMotorVal() {
  digitalWrite(motorIn1Val, LOW);
  digitalWrite(motorIn2Val, LOW);
  analogWrite(motorEnaVal, 0);
}

// -------------------------------------------------------
void updateStateVal() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseUrlVal) + deviceKeyVal + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.PUT("\"" + getStateStringVal(currentStateVal) + "\"");
  http.end();
}

// -------------------------------------------------------
void sendSensorDataVal() {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(firebaseUrlVal) + deviceKeyVal + "/sensorData.json";

  String json = "{";
  json += "\"macAddress\":\"" + realMacVal + "\",";
  json += "\"temperature\":" + String(tempVal, 1) + ",";
  json += "\"humidity\":" + String(humidityVal, 1) + ",";
  json += "\"lightLevel\":" + String(lightLevelVal, 1) + ",";
  json += "\"rain\":" + String(rainDetectedVal ? "true" : "false") + ",";
  json += "\"state\":\"" + getStateStringVal(currentStateVal) + "\"";
  json += "}";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.PUT(json);
  http.end();
}

// -------------------------------------------------------
String getStateStringVal(ClotheslineStateVal s) {
  if (s == Extended) return "extended";
  if (s == Retracted) return "retracted";
  return "moving";
}

// -------------------------------------------------------
void printDebugVal() {
  Serial.println("---- SmartPayan Status ----");
  Serial.printf("AutoMode: %s\n", autoModeVal ? "true" : "false");
  Serial.printf("Slider: %.2f\n", sliderValueVal);
  Serial.printf("State: %s\n", getStateStringVal(currentStateVal).c_str());
  Serial.printf("RTDB State: %s\n", getStateStringVal(rtdbStateVal).c_str());
  Serial.printf("Temp: %.1f\n", tempVal);
  Serial.printf("Humidity: %.1f\n", humidityVal);
  Serial.printf("Light: %.1f (mapped: 0-1000)\n", lightLevelVal);
  Serial.printf("Rain: %s\n", rainDetectedVal ? "YES" : "NONE");
  Serial.println("--------------------------\n");
}
