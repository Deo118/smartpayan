/*  
  SmartPayan v4 — Full RTDB Sync + Supabase Integration + Heartbeat System
  (Direct rewrite — preserves existing behavior; includes manual-control notifications
   and cause-specific auto notifications exactly as requested)
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>

// === WIFI ===
const char* wifiSsidVal = "PLDTHOMEFIBRGcfn2";
const char* wifiPasswordVal = "PLDTWIFIDizon12162404";

// === FIREBASE RTDB ===
const char* firebaseUrlVal =
  "https://smartpayan-f7ea7-default-rtdb.asia-southeast1.firebasedatabase.app/devices/";

// === SUPABASE EDGE FUNCTIONS ===
const char* supabaseNotifUrl =
  "https://dbwhtzoahlzgpiuhqvlv.supabase.co/functions/v1/send-notif";

const char* supabaseHeartbeatUrl =
  "https://dbwhtzoahlzgpiuhqvlv.supabase.co/functions/v1/heartbeat";

// Use the ANON key you provided
const char* supabaseAnonKey =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRid2h0em9haGx6Z3BpdWhxdmx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0NzM5ODYsImV4cCI6MjA4MDA0OTk4Nn0.Ny81j8nYmPteq6apMqIsJAHaNT2erIkXPNBDe7UCvP8";

// === PINS ===
#define dhtPinVal 4
#define dhtTypeVal DHT22
#define rainAnalogPinVal 34
#define rainDigitalPinVal 35
#define motorIn1Val 25
#define motorIn2Val 26
#define motorEnaVal 27
#define i2cSdaVal 21
#define i2cSclVal 22

// === CONSTANTS / TIMINGS ===
int rainThresholdVal = 2500;
int sensorReadIntervalVal = 5000;
int commandReadIntervalVal = 1000;
int dataUpdateIntervalVal = 10000;
int heartbeatIntervalVal = 20000;
int motorSpeedVal = 80;

// notification cooldown (ms) - prevents repeated notifications within this window
const unsigned long notificationCooldownMs = 1000UL;

// === OBJECTS ===
DHT dhtVal(dhtPinVal, dhtTypeVal);
BH1750 lightMeterVal;

enum ClotheslineStateVal { Extended, Retracted, Moving };
ClotheslineStateVal currentStateVal = Retracted;
ClotheslineStateVal rtdbStateVal = Retracted;

// Track last-notified state to avoid duplicate notifications
ClotheslineStateVal lastNotifiedState = Retracted;

// Track previous state written to RTDB to avoid repeated PUTs
ClotheslineStateVal previousStateForDb = Retracted;

bool autoModeVal = true;
float sliderValueVal = 0.0;

float tempVal = 0;
float humidityVal = 0;
float luxRawVal = 0;
float lightLevelVal = 0;
bool rainDetectedVal = false;

// === Device info ===
String realMacVal;
String deviceKeyVal;

// === timers ===
unsigned long lastSensorReadVal = 0;
unsigned long lastDataUpdateVal = 0;
unsigned long lastCommandReadVal = 0;
unsigned long lastHeartbeatVal = 0;
unsigned long lastNotificationSentAt = 0;
bool hasSentOnlineNotification = false;

// === Manual action tracking ===
bool manualActionTriggered = false;
String manualActionType = ""; // "extend" or "retract"

// -------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(10);
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
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(200);
  }

  realMacVal = WiFi.macAddress();
  deviceKeyVal = realMacVal;
  deviceKeyVal.replace(":", "_");

  Serial.println("\nConnected as:");
  Serial.println(deviceKeyVal);

  // Initialize tracking variables
  lastNotifiedState = currentStateVal;
  previousStateForDb = currentStateVal;
  lastNotificationSentAt = 0;
}

// -------------------------------------------------------
void loop() {
  unsigned long ms = millis();

  if (ms - lastSensorReadVal >= (unsigned long)sensorReadIntervalVal) {
    lastSensorReadVal = ms;
    readSensorVals();
  }

  if (ms - lastCommandReadVal >= (unsigned long)commandReadIntervalVal) {
    lastCommandReadVal = ms;
    readCommandsVal();
    readRtdbStateVal();
  }

  if (ms - lastDataUpdateVal >= (unsigned long)dataUpdateIntervalVal) {
    lastDataUpdateVal = ms;
    sendSensorDataVal();
  }

  // Heartbeat 
  if (ms - lastHeartbeatVal >= (unsigned long)heartbeatIntervalVal) {
    lastHeartbeatVal = ms;
    sendHeartbeatVal();
  }

  applyControlLogicVal();

  delay(10);
}

// -------------------------------------------------------
// HEARTBEAT
// -------------------------------------------------------
void sendHeartbeatVal() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Heartbeat] No WiFi.");
    return;
  }

  HTTPClient http;
  http.begin(supabaseHeartbeatUrl);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + supabaseAnonKey);

  String json = "{\"device_id\":\"" + deviceKeyVal + "\"," 
                "\"mac_address\":\"" + realMacVal + "\"}";

  int code = http.POST(json);
  String resp = http.getString();
  Serial.printf("[Heartbeat] %d\n", code);
  Serial.println(resp);

  http.end();
}

// -------------------------------------------------------
// NOTIFICATIONS
// returns true on HTTP 2xx success, false otherwise
// -------------------------------------------------------
bool sendSupabaseNotification(String title, String message, String eventType) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Supabase] No WiFi, skipping notification.");
    return false;
  }

  // Rate-limit notifications to avoid spamming
  unsigned long now = millis();
  if (now - lastNotificationSentAt < notificationCooldownMs) {
    Serial.println("[Supabase] Notification suppressed by cooldown.");
    return false;
  }

  HTTPClient http;
  http.begin(supabaseNotifUrl);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + supabaseAnonKey);

  String body = "{\"title\":\"" + title + "\"," 
                "\"message\":\"" + message + "\"," 
                "\"event_type\":\"" + eventType + "\"," 
                "\"device_id\":\"" + deviceKeyVal + "\"}";

  int code = http.POST(body);
  String resp = http.getString();

  Serial.printf("[Supabase] HTTP %d\n", code);
  Serial.println(resp);

  http.end();

  if (code == 401) {
    Serial.println("[ERROR] Supabase returned 401 Invalid JWT.");
  }

  if (code >= 200 && code < 300) {
    lastNotificationSentAt = now;
    return true;
  } else {
    return false;
  }
}

// -------------------------------------------------------
void readSensorVals() {
  float t = dhtVal.readTemperature();
  float h = dhtVal.readHumidity();

  if (!isnan(t)) tempVal = t;
  if (!isnan(h)) humidityVal = h;

  float lux = lightMeterVal.readLightLevel();
  if (lux >= 0) luxRawVal = lux;

  // Map 0-10000 lux => 0-1000 (as before)
  lightLevelVal = min(10000.0f, luxRawVal) / 10.0f;

  int a = analogRead(rainAnalogPinVal);
  int d = digitalRead(rainDigitalPinVal);

  bool prev = rainDetectedVal;
  rainDetectedVal = (a < rainThresholdVal) || (d == LOW);

  // If rain starts, send immediate sensor update + notify if state changes
  if (rainDetectedVal && !prev) {
    sendSensorDataVal();
  }

  // Keep serial debug consistent (will show live sensor values)
  printDebugVal();
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

  autoModeVal = payload.indexOf("\"autoMode\":true") != -1;

  int p = payload.indexOf("clotheslinePosition");
  if (p != -1) {
    int col = payload.indexOf(":", p);
    int end = payload.indexOf(",", col);
    if (end == -1) end = payload.indexOf("}", col);
    sliderValueVal = payload.substring(col + 1, end).toFloat();
  }

  // MANUAL CONTROL HANDLING: mark manualActionTriggered when app requests change
  if (!autoModeVal) {
    // RETRACT (manual)
    if (sliderValueVal <= 0.1f && currentStateVal != Retracted) {
      manualActionTriggered = true;
      manualActionType = "retract";
      retractVal();
    }
    // EXTEND (manual)
    else if (sliderValueVal >= 0.9f && currentStateVal != Extended) {
      manualActionTriggered = true;
      manualActionType = "extend";
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
  // else ignore unknown / moving states

  // If app changed state manually, ESP follows (only when NOT auto)
  if (rtdbStateVal != currentStateVal && !autoModeVal) {
    manualActionTriggered = true;
    manualActionType = (rtdbStateVal == Extended ? "extend" : "retract");

    if (rtdbStateVal == Extended) extendVal();
    else retractVal();
  }
}

// -------------------------------------------------------
void applyControlLogicVal() {
  if (!autoModeVal) return;

  bool shouldRetract = false;
  bool shouldExtend = false;

  if (rainDetectedVal) shouldRetract = true;
  else if (lightLevelVal < 200) shouldRetract = true;
  else if (humidityVal > 85) shouldRetract = true;
  else shouldExtend = true;

  if (shouldRetract && currentStateVal != Retracted) retractVal();
  if (shouldExtend && currentStateVal != Extended) extendVal();
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
String getRetractCause() {
  bool rain = rainDetectedVal;
  bool lowLight = (lightLevelVal < 200);
  bool highHumidity = (humidityVal > 85);

  // Build cause description
  String cause = "";

  if (rain) {
    cause += "Rain";
  }
  if (lowLight) {
    if (cause.length() > 0) cause += " + ";
    cause += "Low Light";
  }
  if (highHumidity) {
    if (cause.length() > 0) cause += " + ";
    cause += "High Humidity";
  }

  // Trim and format
  cause.trim();

  if (cause.length() == 0) cause = "Unknown Condition";
  return cause;
}

// -------------------------------------------------------
void updateStateVal() {
  if (WiFi.status() != WL_CONNECTED) return;

  // Only write to RTDB if needed
  if (currentStateVal == previousStateForDb) {

    // Notification check (state didn't change but might not have been notified yet)
    if (currentStateVal != lastNotifiedState) {
      unsigned long now = millis();
      if (now - lastNotificationSentAt >= notificationCooldownMs) {

        // If a manual action triggered this state, prefer manual notification
        if (manualActionTriggered) {
          String title = "Manual Control Activated";
          String message = (manualActionType == "extend")
                             ? "User extended the clothesline manually via the app."
                             : "User retracted the clothesline manually via the app.";

          if (sendSupabaseNotification(title, message, "manual_control")) {
            lastNotifiedState = currentStateVal;
          }
          // Reset manual flag irrespective of http success to avoid duplicate sends later
          manualActionTriggered = false;
          manualActionType = "";
        } else {
          // Automatic or unknown cause — send cause-specific
          if (currentStateVal == Extended) {
            if (sendSupabaseNotification("Clothesline Update",
                                         "Good weather condition. Clothesline extended.",
                                         "clothesline_state")) {
              lastNotifiedState = currentStateVal;
            }
          } else {
            String cause = getRetractCause();
            String msg = cause + " detected. Clothesline retracted.";
            if (sendSupabaseNotification("Clothesline Update", msg, "clothesline_state")) {
              lastNotifiedState = currentStateVal;
            }
          }
        }

      } else {
        Serial.println("[UpdateState] Notification suppressed by cooldown.");
      }
    }
    return;
  }

  // Write to RTDB because state changed
  String url = String(firebaseUrlVal) + deviceKeyVal + "/sensorData/state.json";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  String payload = "\"" + getStateStringVal(currentStateVal) + "\"";
  int code = http.PUT(payload);
  String resp = http.getString();
  Serial.printf("[RTDB PUT State] %d\n", code);
  Serial.println(resp);
  http.end();

  previousStateForDb = currentStateVal;

  // Send logically accurate notifications after DB write (if needed)
  if (currentStateVal != lastNotifiedState) {

    // Manual action notification takes precedence
    if (manualActionTriggered) {
      String title = "Manual Control Activated";
      String message = (manualActionType == "extend")
                         ? "User extended the clothesline manually via the app."
                         : "User retracted the clothesline manually via the app.";

      if (sendSupabaseNotification(title, message, "manual_control")) {
        lastNotifiedState = currentStateVal;
      }
      manualActionTriggered = false;
      manualActionType = "";
    } else {
      // Automatic cause-based notification
      if (currentStateVal == Extended) {
        if (sendSupabaseNotification("Clothesline Update",
                                     "Good weather condition. Clothesline extended.",
                                     "clothesline_state")) {
          lastNotifiedState = currentStateVal;
        }
      } else {
        String cause = getRetractCause();
        String msg = cause + " detected. Clothesline retracted.";
        if (sendSupabaseNotification("Clothesline Update", msg, "clothesline_state")) {
          lastNotifiedState = currentStateVal;
        }
      }
    }
  }
}

// -------------------------------------------------------
void sendSensorDataVal() {
  if (WiFi.status() != WL_CONNECTED) {
    hasSentOnlineNotification = false;  // WiFi down = device is offline
    return;
  }

  String url = String(firebaseUrlVal) + deviceKeyVal + "/sensorData.json";

  String json = "{\"macAddress\":\"" + realMacVal + "\"," 
                "\"temperature\":" + String(tempVal, 1) + "," 
                "\"humidity\":" + String(humidityVal, 1) + "," 
                "\"lightLevel\":" + String(lightLevelVal, 1) + "," 
                "\"rain\":" + String(rainDetectedVal ? "true" : "false") + "," 
                "\"state\":\"" + getStateStringVal(currentStateVal) + "\"}";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  int code = http.PUT(json);
  String resp = http.getString();
  http.end();

  Serial.printf("[Sensor PUT] %d\n", code);
  Serial.println(resp);

  // ONLINE DETECTION LOGIC
  if (code > 0 && code < 300) {   // RTDB write succeeded
      if (!hasSentOnlineNotification) {
          sendSupabaseNotification(
              "Device Online",
              "Your device is now back online.",
              "device_online"
          );
          hasSentOnlineNotification = true;
      }
  } else {
      // RTDB write failed → device considered offline
      hasSentOnlineNotification = false;
  }
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
  Serial.printf("Light: %.1f (mapped)\n", lightLevelVal);
  Serial.printf("Rain: %s\n", rainDetectedVal ? "YES" : "NONE");
  Serial.println("--------------------------\n");
}
