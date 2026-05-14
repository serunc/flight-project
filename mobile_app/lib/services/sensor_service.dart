import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  AccelerometerEvent? _latestAccelerometer;
  MagnetometerEvent? _latestMagnetometer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  void start() {
    print('🌀 Sensor Service: Starting sensor listeners...');
    _accelerometerSubscription ??= accelerometerEventStream().listen((event) {
      _latestAccelerometer = event;
      print('📊 Accelerometer: x=${event.x.toStringAsFixed(2)}, y=${event.y.toStringAsFixed(2)}, z=${event.z.toStringAsFixed(2)}');
    });
    _magnetometerSubscription ??= magnetometerEventStream().listen((event) {
      _latestMagnetometer = event;
      print('🧲 Magnetometer: x=${event.x.toStringAsFixed(2)}, y=${event.y.toStringAsFixed(2)}, z=${event.z.toStringAsFixed(2)}');
    });
    print('✅ Sensor Service: Sensor listeners started');
  }

  void stop() {
    print('🛑 Sensor Service: Stopping sensor listeners...');
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _magnetometerSubscription = null;
    print('✅ Sensor Service: Sensor listeners stopped');
  }

  double getPitchAngle() {
    final reading = _latestAccelerometer;
    if (reading == null) {
      print('⚠️ Sensor Service: No accelerometer reading available');
      return 0.0;
    }

    final pitchRadians = atan2(
      -reading.x,
      sqrt(reading.y * reading.y + reading.z * reading.z),
    );
    final pitchDegrees = pitchRadians * 180 / pi;
    print('📐 Sensor Service: Pitch angle calculated: ${pitchDegrees.toStringAsFixed(2)}°');
    return pitchDegrees;
  }

  double? getHeadingDeg() {
    final accel = _latestAccelerometer;
    final mag = _latestMagnetometer;
    if (accel == null || mag == null) {
      print('⚠️ Sensor Service: Missing accelerometer or magnetometer data for heading calculation');
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
