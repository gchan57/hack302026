import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class MotionScreen extends StatefulWidget {
  @override
  _MotionScreenState createState() => _MotionScreenState();
}

class _MotionScreenState extends State<MotionScreen> {

  final DatabaseReference ref =
      FirebaseDatabase.instance.ref("motion_data");

  double magnitude = 0;
  bool fallDetected = false;
  String status = "Unknown";

  String getStatus(double magnitude) {
    if (magnitude < 5000) {
      return "Free Fall";
    } else if (magnitude >= 25000 && magnitude <= 32000) {
      return "Impact";
    } else if (magnitude >= 20000 && magnitude < 25000) {
      return "Shake";
    } else if (magnitude >= 17000 && magnitude < 20000) {
      return "Walking";
    } else {
      return "Idle";
    }
  }

  @override
  void initState() {
    super.initState();

    ref.onValue.listen((event) {
      final data = event.snapshot.value as Map;

      double mag = (data["magnitude"]).toDouble();
      bool fall = data["fall_detected"];

      setState(() {
        magnitude = mag;
        fallDetected = fall;
        status = getStatus(mag);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Motion Monitor"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Text(
              status,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),

            SizedBox(height: 20),

            Text(
              "Magnitude: ${magnitude.toStringAsFixed(2)}",
              style: TextStyle(fontSize: 22),
            ),

            SizedBox(height: 30),

            fallDetected
                ? Container(
                    padding: EdgeInsets.all(16),
                    color: Colors.red,
                    child: Text(
                      "FALL DETECTED",
                      style: TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : Container(
                    padding: EdgeInsets.all(16),
                    color: Colors.green,
                    child: Text(
                      "SAFE",
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                      ),
                    ),
                  )
          ],
        ),
      ),
    );
  }
}