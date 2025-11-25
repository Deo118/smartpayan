#include <WiFi.h>
#include <HTTPClient.h>

// ===== WiFi =====
const char* ssid = "PLDTHOMEFIBRGcfn2";
const char* password = "PLDTWIFIDizon12162404";

// ===== Firebase =====
const char* firebaseURL = "https://smartpayan-f7ea7-default-rtdb.asia-southeast1.firebasedatabase.app/devices/";  // Base URL for devices
String deviceId = "44:1D:64:F5:3E:F8";  // Hardcode your ESP32's MAC address here (match Flutter setup)

// ===== Pins =====
const int buttonPin = 25;     // Rain toggle button
const int potPin = 34;        // Light level potentiometer
const int humUpPin = 26;
const int humDownPin = 27;
const int tempUpPin = 32;
const int tempDownPin = 33;

// ===== Sensor values =====
int humidity = 50;
float temperature = 25.0;
bool rain = false;
double clotheslinePosition = 0.5;  // From commands (for debugging only)
bool autoMode = true;  // From commands (for debugging only)

// ===== Button state tracking =====
bool prevRainBtn = HIGH;
bool prevHumUp = HIGH;
bool prevHumDown = HIGH;
bool prevTempUp = HIGH;
bool prevTempDown = HIGH;

// ===== Timing =====
unsigned long lastSendTime = 0;
const unsigned long sendInterval = 2000;  // Send every 2 seconds

void setup() {
  Serial.begin(115200);

  // Configure pins
  pinMode(buttonPin, INPUT_PULLUP);
  pinMode(humUpPin, INPUT_PULLUP);
  pinMode(humDownPin, INPUT_PULLUP);
  pinMode(tempUpPin, INPUT_PULLUP);
  pinMode(tempDownPin, INPUT_PULLUP);

  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected!");
}

void loop() {
  // Update rain status (toggle on press)
  bool rainBtn = digitalRead(buttonPin);
  if (rainBtn == LOW && prevRainBtn == HIGH) {
    rain = !rain;
  }
  prevRainBtn = rainBtn;

  // Read potentiometer and map to 0-1000
  int potValue = analogRead(potPin);
  potValue = map(potValue, 0, 4095, 0, 1000);

  // Update humidity (increment/decrement on press)
  bool humUpBtn = digitalRead(humUpPin);
  if (humUpBtn == LOW && prevHumUp == HIGH) {
    humidity = constrain(humidity + 1, 0, 100);
  }
  prevHumUp = humUpBtn;

  bool humDownBtn = digitalRead(humDownPin);
  if (humDownBtn == LOW && prevHumDown == HIGH) {
    humidity = constrain(humidity - 1, 0, 100);
  }
  prevHumDown = humDownBtn;

  // Update temperature (increment/decrement on press)
  bool tempUpBtn = digitalRead(tempUpPin);
  if (tempUpBtn == LOW && prevTempUp == HIGH) {
    temperature = constrain(temperature + 0.5, 0.0, 50.0);
  }
  prevTempUp = tempUpBtn;

  bool tempDownBtn = digitalRead(tempDownPin);
  if (tempDownBtn == LOW && prevTempDown == HIGH) {
    temperature = constrain(temperature - 0.5, 0.0, 50.0);
  }
  prevTempDown = tempDownBtn;

  // Read commands from RTDB (for debugging; no hardware actions)
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String commandURL = String(firebaseURL) + deviceId + "/commands.json";
    http.begin(commandURL);
    int httpResponseCode = http.GET();
    if (httpResponseCode > 0) {
      String payload = http.getString();
      // Simple parsing (use ArduinoJson for better handling)
      if (payload.indexOf("\"clotheslinePosition\":") != -1) {
        int start = payload.indexOf("\"clotheslinePosition\":") + 21;
        int end = payload.indexOf(",", start);
        clotheslinePosition = payload.substring(start, end).toDouble();
      }
      if (payload.indexOf("\"autoMode\":") != -1) {
        int start = payload.indexOf("\"autoMode\":") + 10;
        int end = payload.indexOf("}", start);
        autoMode = payload.substring(start, end) == "true";
      }
    }
    http.end();
  }

  // Check if it's time to send data
  unsigned long currentTime = millis();
  if (currentTime - lastSendTime >= sendInterval) {
    lastSendTime = currentTime;

    // Get MAC address
    String macAddress = WiFi.macAddress();

    // Prepare JSON for sensor data
    String jsonData = "{\"rain\": " + String(rain ? "true" : "false") +
                      ", \"lightLevel\": " + String(potValue) +
                      ", \"humidity\": " + String(humidity) +
                      ", \"temperature\": " + String(temperature) +
                      ", \"macAddress\": \"" + macAddress + "\"}";

    // Send to RTDB
    if (WiFi.status() == WL_CONNECTED) {
      HTTPClient http;
      String sensorURL = String(firebaseURL) + deviceId + "/sensorData.json";
      http.begin(sensorURL);
      http.addHeader("Content-Type", "application/json");
      int httpResponseCode = http.PUT(jsonData);
      if (httpResponseCode > 0) {
        Serial.print("Sensor data sent: ");
        Serial.println(httpResponseCode);
      } else {
        Serial.print("Error sending sensor data: ");
        Serial.println(httpResponseCode);
      }
      http.end();
    }

    // Print for debugging (including commands)
    Serial.print("Rain: "); Serial.println(rain);
    Serial.print("Light: "); Serial.println(potValue);
    Serial.print("Humidity: "); Serial.println(humidity);
    Serial.print("Temperature: "); Serial.println(temperature);
    Serial.print("Clothesline Pos (from app): "); Serial.println(clotheslinePosition);
    Serial.print("Auto Mode (from app): "); Serial.println(autoMode);
  }

  delay(10);  // Small delay for responsiveness
}