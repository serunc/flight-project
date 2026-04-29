import 'dart:math';

class AircraftPositionEstimator {
  const AircraftPositionEstimator();

  double? estimateDistanceMeters({
    required double pitchAngleDeg,
    required double estimatedAltitudeMeters,
  }) {
    if (pitchAngleDeg <= 0) {
      return null;
    }

    final pitchAngleRad = _degreesToRadians(pitchAngleDeg);
    final tangent = tan(pitchAngleRad);

    return estimatedAltitudeMeters / tangent;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180.0;
}
