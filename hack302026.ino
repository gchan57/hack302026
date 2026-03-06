#include <Firebase_ESP_Client.h>
#include <MPU6050.h>
#include <TinyGPSPlus.h>
#include <WiFi.h>
#include <Wire.h>

/* ============================================================
   GUARDIAN — Smart Fall Detection & Alert System  (SDG 3)
   Hardware: ESP32 + MPU6050 + GPS (NEO-6M)
   ============================================================ */

/* ---------------- WiFi ---------------- */
#define WIFI_SSID "cmf"
#define WIFI_PASSWORD "87654321"

/* ------------- Firebase --------------- */
#define API_KEY "AIzaSyCZHVvZhiTPFR7bHHAWIImAxRzSEuC0rw8"
#define DATABASE_URL                                                           \
  "hack30-93be7-default-rtdb.asia-southeast1.firebasedatabase.app"

/* --- Fall Detection Threshold (raw G units) ---
   MPU6050 default sensitivity = 16384 LSB/g
   Threshold = magnitude in raw units
   2.5g shock  → 16384 * 2.5 ≈ 40960
   Tune this value higher if false positives occur. */
#define FALL_THRESHOLD_G 2.5f // in G units

/* -------------------------------------------- */
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

TinyGPSPlus gps;
HardwareSerial gpsSerial(2); // RX=16, TX=17

MPU6050 mpu;

unsigned long lastSendMs = 0;
unsigned long fallCooldownMs = 0;
bool fallDetected = false;

const unsigned long SEND_INTERVAL = 10000; // send sensor data every 10 s
const unsigned long FALL_COOLDOWN = 30000; // re-arm fall detector after 30 s

/* ============================================================ */

void setup() {
  Serial.begin(115200);

  /* GPS serial */
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);
  Serial.println("GPS Starting...");

  /* I2C + MPU6050 */
  Wire.begin();
  mpu.initialize();
  Serial.println(mpu.testConnection() ? "MPU6050 OK" : "MPU6050 FAILED");

  /* WiFi */
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(500);
  }
  Serial.println("\nWiFi Connected: " + WiFi.localIP().toString());

  /* Firebase */
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.signer.test_mode = true;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Serial.println("Guardian device ready!");
}

/* ============================================================ */

float computeMagnitudeG(int16_t ax, int16_t ay, int16_t az) {
  float gx = ax / 16384.0f;
  float gy = ay / 16384.0f;
  float gz = az / 16384.0f;
  return sqrt(gx * gx + gy * gy + gz * gz);
}

/* ============================================================ */

void loop() {
  /* ---- Drain GPS serial ---- */
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());

    if (gps.location.isUpdated()) {
      Serial.printf("[GPS] %.6f, %.6f  Speed:%.1f km/h  Alt:%.0f m  Sats:%d\n",
                    gps.location.lat(), gps.location.lng(), gps.speed.kmph(),
                    gps.altitude.meters(), gps.satellites.value());
    }
  }

  /* ---- Read MPU6050 ---- */
  int16_t ax, ay, az;
  mpu.getAcceleration(&ax, &ay, &az);
  float magG = computeMagnitudeG(ax, ay, az);

  /* ---- Fall Detection ---- */
  bool cooldownOver = (millis() - fallCooldownMs > FALL_COOLDOWN);

  if (magG > FALL_THRESHOLD_G && !fallDetected && cooldownOver) {
    fallDetected = true;
    fallCooldownMs = millis();

    Serial.printf("*** FALL DETECTED! Magnitude: %.2f G ***\n", magG);

    /* Log fall event to Firebase */
    if (Firebase.ready()) {
      FirebaseJson fallJson;
      fallJson.set("timestamp", (int)millis());
      fallJson.set("magnitude", magG);
      if (gps.location.isValid()) {
        fallJson.set("latitude", gps.location.lat());
        fallJson.set("longitude", gps.location.lng());
      }

      String path = "/fall_events/" + String(millis());
      if (Firebase.RTDB.setJSON(&fbdo, path, &fallJson))
        Serial.println("Fall event logged to Firebase");
      else
        Serial.println("Fall log error: " + fbdo.errorReason());
    }
  }

  /* Reset fall flag after cooldown ONLY IF it's currently true AND 30 seconds
   * have actually passed since we recorded the fall */
  if (fallDetected && (millis() - fallCooldownMs > FALL_COOLDOWN)) {
    fallDetected = false;
    Serial.println("Fall alert reset — Back to monitoring.");
  }

  /* ---- Periodic sensor data upload (every 10 s) ---- */
  if (Firebase.ready() && millis() - lastSendMs > SEND_INTERVAL) {
    lastSendMs = millis();

    FirebaseJson json;
    json.set("ax", ax);
    json.set("ay", ay);
    json.set("az", az);
    json.set("magnitude_g", magG);
    json.set("fall_detected", fallDetected);
    json.set("timestamp", (int)millis());

    if (gps.location.isValid()) {
      json.set("latitude", gps.location.lat());
      json.set("longitude", gps.location.lng());
      json.set("altitude_m", gps.altitude.meters());
      json.set("speed_kmh", gps.speed.kmph());
      json.set("satellites", (int)gps.satellites.value());
    }

    if (Firebase.RTDB.setJSON(&fbdo, "sensor_data", &json))
      Serial.printf("[Firebase] Updated — Mag: %.2f G, Fall: %s\n", magG,
                    fallDetected ? "YES" : "NO");
    else
      Serial.println("Firebase Error: " + fbdo.errorReason());
  }
}
