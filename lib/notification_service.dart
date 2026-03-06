import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Singleton service that manages local push notifications for Guardian app.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'guardian_alerts';
  static const _channelName = 'Guardian Alerts';
  static const _channelDesc = 'Fall detection emergency alerts';

  static const _kRed = Color(0xFFDC2626);
  static const _kOrange = Color(0xFFF97316);
  static const _vibration = [0, 500, 200, 500, 200, 500];

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Create Android channel upfront
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// 🚨 High-priority fall alert — red LED, strong vibration.
  Future<void> showFallAlert({double? lat, double? lng}) async {
    await init();

    final locationText = (lat != null && lng != null && lat != 0 && lng != 0)
        ? 'Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
        : 'GPS location unavailable';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'FALL DETECTED',
      icon: '@mipmap/ic_launcher',
      color: _kRed,
      enableLights: true,
      ledColor: _kRed,
      ledOnMs: 300,
      ledOffMs: 200,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(_vibration),
      styleInformation: BigTextStyleInformation(
        'Emergency assistance may be needed.\n$locationText',
        summaryText: 'Guardian Alert',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      1001,
      '🚨 FALL DETECTED!',
      'Emergency assistance may be needed. $locationText',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// ⚠️ High-G impact warning.
  Future<void> showImpactAlert({double? mag}) async {
    await init();

    final magText = mag != null
        ? '${mag.toStringAsFixed(2)} G impact detected'
        : 'High-G impact detected';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      color: _kOrange,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    await _plugin.show(
      1002,
      '⚠️ High Impact Warning',
      '$magText — please check on the person.',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
