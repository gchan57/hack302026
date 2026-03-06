import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'avatar_widget.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0284C7),
          surface: Colors.white,
        ),
      ),
      home: const MotionScreen(),
    );
  }
}

// Model for a fall event entry
class FallEvent {
  final String id;
  final double latitude;
  final double longitude;
  final double magnitude;
  final int timestamp;

  FallEvent({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.magnitude,
    required this.timestamp,
  });

  factory FallEvent.fromMap(String id, Map map) {
    return FallEvent(
      id: id,
      latitude: double.tryParse(map['latitude']?.toString() ?? '0') ?? 0,
      longitude: double.tryParse(map['longitude']?.toString() ?? '0') ?? 0,
      magnitude: double.tryParse(map['magnitude']?.toString() ?? '0') ?? 0,
      timestamp: int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0,
    );
  }
}

class MotionScreen extends StatefulWidget {
  const MotionScreen({super.key});

  @override
  State<MotionScreen> createState() => _MotionScreenState();
}

class _MotionScreenState extends State<MotionScreen> {
  final DatabaseReference _sensorRef = FirebaseDatabase.instance.ref(
    "sensor_data",
  );
  final DatabaseReference _fallEventsRef = FirebaseDatabase.instance.ref(
    "fall_events",
  );

  WebViewController? _controller;

  // Sensor data fields
  double magnitudeG = 0.0;
  bool fallDetected = false;
  String status = "Connecting...";
  int ax = 0, ay = 0, az = 0, timestamp = 0;
  double lat = 0.0, lng = 0.0;
  double altitudeM = 0.0;
  double speedKmh = 0.0;
  int satellites = 0;
  String lastCoords = "";

  // Fall events history
  List<FallEvent> fallEvents = [];

  // Track previous fall/impact state to avoid repeated notifications
  bool _prevFallDetected = false;
  String _prevStatus = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));

    _listenSensorData();
    _listenFallEvents();
  }

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _listenSensorData() {
    _sensorRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;
      final map = data as Map<dynamic, dynamic>;

      setState(() {
        ax = int.tryParse(map["ax"]?.toString() ?? "0") ?? 0;
        ay = int.tryParse(map["ay"]?.toString() ?? "0") ?? 0;
        az = int.tryParse(map["az"]?.toString() ?? "0") ?? 0;
        timestamp = int.tryParse(map["timestamp"]?.toString() ?? "0") ?? 0;
        lat = double.tryParse(map["latitude"]?.toString() ?? "0.0") ?? 0.0;
        lng = double.tryParse(map["longitude"]?.toString() ?? "0.0") ?? 0.0;
        altitudeM =
            double.tryParse(map["altitude_m"]?.toString() ?? "0.0") ?? 0.0;
        speedKmh =
            double.tryParse(map["speed_kmh"]?.toString() ?? "0.0") ?? 0.0;
        satellites = int.tryParse(map["satellites"]?.toString() ?? "0") ?? 0;

        // Use pre-computed magnitude_g from Firebase directly
        magnitudeG =
            double.tryParse(map["magnitude_g"]?.toString() ?? "0.0") ?? 0.0;

        final fd = map["fall_detected"];
        fallDetected = (fd is bool)
            ? fd
            : (fd.toString().toLowerCase() == 'true');

        // G-force based thresholds
        status = getStatus(magnitudeG);

        // ── Notifications ─────────────────────────────────────────────
        if (fallDetected && !_prevFallDetected) {
          NotificationService.instance.showFallAlert(lat: lat, lng: lng);
        } else if (status == 'Impact' &&
            _prevStatus != 'Impact' &&
            !fallDetected) {
          NotificationService.instance.showImpactAlert(mag: magnitudeG);
        }
        _prevFallDetected = fallDetected;
        _prevStatus = status;

        if (lat != 0 && lng != 0) {
          String coordKey = "$lat,$lng";
          if (coordKey != lastCoords) {
            lastCoords = coordKey;
            _controller?.loadHtmlString(_buildMapHtml(lat, lng));
          }
        }
      });
    });
  }

  void _listenFallEvents() {
    _fallEventsRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return;
      final map = data as Map<dynamic, dynamic>;

      final List<FallEvent> events = [];
      map.forEach((key, value) {
        if (value is Map) {
          events.add(FallEvent.fromMap(key.toString(), value));
        }
      });

      // Sort by timestamp descending (most recent first)
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        fallEvents = events;
      });
    });
  }

  /// G-force thresholds based on real sensor data:
  /// - Normal standing/resting ≈ 1.0 G
  /// - Walking ≈ 1.2–1.8 G
  /// - Fall events observed at 2.5–3.3 G
  /// - Free fall (near 0 G) < 0.3 G
  String getStatus(double mag) {
    if (mag >= 2.5) return "Impact";
    if (mag >= 1.2) return "Walking";
    if (mag < 0.3) return "Free Fall";
    return "Idle";
  }

  String _buildMapHtml(double lat, double lng) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>html,body,#map{margin:0;padding:0;width:100%;height:100%;}</style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map').setView([$lat, $lng], 16);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);
    L.marker([$lat, $lng]).addTo(map)
      .bindPopup('Current Location').openPopup();
  </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final cfg = getStatusConfig();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          "GUARDIAN",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // --- ANIMATED AVATAR ---
            AvatarWidget(
              status: status,
              fallDetected: fallDetected,
              color: cfg.color,
            ),

            const SizedBox(height: 8),
            Text(
              cfg.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: cfg.color,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cfg.description,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              "${magnitudeG.toStringAsFixed(2)} G  •  ${speedKmh.toStringAsFixed(1)} km/h  •  ${altitudeM.toStringAsFixed(0)} m  •  🛰 $satellites",
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),

            const SizedBox(height: 20),

            // --- MAP CONTAINER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: (lat != 0 && lng != 0)
                      ? WebViewWidget(controller: _controller!)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.location_searching,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Waiting for GPS signal...",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),

            // --- OPEN IN MAPS BUTTON ---
            if (lat != 0 && lng != 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openInMaps,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text("Open in Google Maps"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 10),

            // --- AXES DATA ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _axisCard("X-AXIS", ax, Colors.redAccent),
                  _axisCard("Y-AXIS", ay, Colors.greenAccent),
                  _axisCard("Z-AXIS", az, Colors.orangeAccent),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Text(
              "Last Sync: $timestamp",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),

            const SizedBox(height: 20),

            // --- FALL EVENTS HISTORY ---
            if (fallEvents.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Text(
                      "Fall Events (${fallEvents.length})",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: fallEvents.length,
                itemBuilder: (context, index) {
                  final e = fallEvents[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${e.magnitude.toStringAsFixed(2)} G  •  t=${e.timestamp}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "${e.latitude.toStringAsFixed(6)}, ${e.longitude.toStringAsFixed(6)}",
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.map_outlined,
                            size: 18,
                            color: Color(0xFF0284C7),
                          ),
                          onPressed: () async {
                            final uri = Uri.parse(
                              "https://www.google.com/maps/search/?api=1&query=${e.latitude},${e.longitude}",
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _axisCard(String label, int val, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: col,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "$val",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  StatusConfig getStatusConfig() {
    if (fallDetected)
      return StatusConfig(
        color: Colors.red,
        icon: Icons.warning,
        label: "FALL!",
        description: "Emergency assistance required",
      );
    if (status == "Impact")
      return StatusConfig(
        color: Colors.orange,
        icon: Icons.crisis_alert,
        label: "IMPACT",
        description: "High-force movement detected",
      );
    if (status == "Walking")
      return StatusConfig(
        color: Colors.blue,
        icon: Icons.directions_walk,
        label: "ACTIVE",
        description: "Elder is currently moving",
      );
    if (status == "Free Fall")
      return StatusConfig(
        color: Colors.deepOrange,
        icon: Icons.arrow_downward,
        label: "FREE FALL",
        description: "Sudden drop detected",
      );
    return StatusConfig(
      color: Colors.green,
      icon: Icons.person,
      label: "SAFE",
      description: "Stable and resting",
    );
  }
}

class StatusConfig {
  final Color color;
  final IconData icon;
  final String label;
  final String description;
  StatusConfig({
    required this.color,
    required this.icon,
    required this.label,
    required this.description,
  });
}
