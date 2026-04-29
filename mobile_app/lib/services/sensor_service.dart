import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  AccelerometerEvent? _latestAccelerometer;
  MagnetometerEvent? _latestMagnetometer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  void start() {
    _accelerometerSubscription ??= accelerometerEventStream().listen((event) {
      _latestAccelerometer = event;
    });
    _magnetometerSubscription ??= magnetometerEventStream().listen((event) {
      _latestMagnetometer = event;
    });
  }

  void stop() {
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _magnetometerSubscription = null;
  }

  double getPitchAngle() {
    final reading = _latestAccelerometer;
    if (reading == null) {
      return 0.0;
    }

    final pitchRadians = atan2(
      -reading.x,
      sqrt(reading.y * reading.y + reading.z * reading.z),
    );
    return pitchRadians * 180 / pi;
  }

  double? getHeadingDeg() {
    final accel = _latestAccelerometer;
    final mag = _latestMagnetometer;
    if (accel == null || mag == null) {
      return null;
    }

    final ax = accel.x;
    final ay = accel.y;
    final az = accel.z;

    final mx = mag.x;
    final my = mag.y;
    final mz = mag.z;

    // Simple tilt compensation with accelerometer + magnetometer.
    final roll = atan2(ay, az);
    final pitch = atan2(-ax, sqrt(ay * ay + az * az));

    final compensatedX = mx * cos(pitch) + mz * sin(pitch);
    final compensatedY = mx * sin(roll) * sin(pitch) +
        my * cos(roll) -
        mz * sin(roll) * cos(pitch);

    var headingDeg = atan2(compensatedY, compensatedX) * 180 / pi;
    if (headingDeg < 0) {
      headingDeg += 360;
    }

    return headingDeg;
  }
}
