import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MotionScreen(),
    );
  }
}

class MotionScreen extends StatefulWidget {
  const MotionScreen({super.key});

  @override
  State<MotionScreen> createState() => _MotionScreenState();
}

class _MotionScreenState extends State<MotionScreen> {
  final DatabaseReference ref = FirebaseDatabase.instance.ref("motion_data");

  double magnitude = 0;
  bool fallDetected = false;
  String status = "Connecting...";

  // Optional: Store other sensor values if needed
  int ax = 0;
  int ay = 0;
  int az = 0;
  int timestamp = 0;

  @override
  void initState() {
    super.initState();
    listenToFirebase();
  }

  void listenToFirebase() {
    ref.onValue.listen(
      (DatabaseEvent event) {
        final data = event.snapshot.value;

        // ── DEEP DIAGNOSTIC ─────────────────────────────────────────────
        print("══════════════════════════════════");
        print("RAW Firebase snapshot: $data");
        print("RAW type: ${data.runtimeType}");
        if (data is Map) {
          print("Top-level keys: ${data.keys.toList()}");
          data.forEach((k, v) {
            print("  key='$k'  value='$v'  type=${v.runtimeType}");
          });
        }
        print("══════════════════════════════════");
        // ────────────────────────────────────────────────────────────────

        if (data == null) {
          print("Firebase returned null — node may be empty or path is wrong.");
          return;
        }

        if (data is! Map) {
          print("Unexpected data type: ${data.runtimeType}. Expected Map.");
          return;
        }

        Map<dynamic, dynamic> map = data;

        // Handle push-key nesting  e.g. { "-Nxabc": { "ax": 1 , ... } }
        // If the map has NO direct sensor keys, assume values are nested records.
        final sensorKeys = {
          "magnitude",
          "ax",
          "ay",
          "az",
          "fall_detected",
          "timestamp",
        };
        final hasDirectKeys = map.keys.any(
          (k) => sensorKeys.contains(k.toString()),
        );

        if (!hasDirectKeys && map.isNotEmpty) {
          // Pick the most-recently-inserted entry (last key)
          final lastEntry = map.entries.last;
          print(
            "No direct sensor keys found. Using nested entry key='${lastEntry.key}'",
          );
          if (lastEntry.value is Map) {
            map = lastEntry.value as Map;
            print("Nested map keys: ${map.keys.toList()}");
          }
        }

        setState(() {
          // magnitude (hardware-provided)
          if (map["magnitude"] != null) {
            magnitude = double.tryParse(map["magnitude"].toString()) ?? 0.0;
          }

          // fall_detected
          if (map["fall_detected"] != null) {
            final fd = map["fall_detected"];
            if (fd is bool) {
              fallDetected = fd;
            } else if (fd is String) {
              fallDetected = fd.toLowerCase() == 'true';
            } else if (fd is num) {
              fallDetected = fd != 0;
            }
          }

          // raw axes
          if (map["ax"] != null) ax = int.tryParse(map["ax"].toString()) ?? 0;
          if (map["ay"] != null) ay = int.tryParse(map["ay"].toString()) ?? 0;
          if (map["az"] != null) az = int.tryParse(map["az"].toString()) ?? 0;
          if (map["timestamp"] != null) {
            timestamp = int.tryParse(map["timestamp"].toString()) ?? 0;
          }

          // Compute magnitude from axes when hardware doesn't send it
          if (map["magnitude"] == null) {
            magnitude = sqrt(ax * ax + ay * ay + az * az).toDouble();
          }

          print(
            "PARSED → ax:$ax ay:$ay az:$az magnitude:$magnitude fallDetected:$fallDetected",
          );
          status = getStatus(magnitude);
        });
      },
      onError: (error) {
        print("Firebase Listen Error: $error");
      },
    );
  }

  String getStatus(double mag) {
    if (mag < 5000) {
      return "Free Fall";
    } else if (mag >= 25000) {
      return "Impact";
    } else if (mag >= 20000) {
      return "Shake";
    } else if (mag >= 15000) {
      return "Walking";
    } else {
      return "Idle";
    }
  }

  Color getStatusColor() {
    switch (status) {
      case "Free Fall":
      case "Impact":
        return Colors.red;
      case "Shake":
        return Colors.orange;
      case "Walking":
        return Colors.blue;
      case "Idle":
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Elder Fall Detection"),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Current Status",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Text(
                status,
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                  color: getStatusColor(),
                ),
              ),
              const SizedBox(height: 40),

              Card(
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    children: [
                      const Text(
                        "Sensor Magnitude",
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        magnitude.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // Optional: Display other sensor values
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Text("AX: $ax"),
                          Text("AY: $ay"),
                          Text("AZ: $az"),
                        ],
                      ),

                      const SizedBox(height: 5),
                      Text(
                        "Timestamp: $timestamp",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 50),

              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: fallDetected ? Colors.red : Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      fallDetected ? Icons.warning : Icons.check_circle,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      fallDetected ? "FALL DETECTED" : "ELDER SAFE",
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
