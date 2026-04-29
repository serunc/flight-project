import 'dart:math';

class TargetCoordinate {
  final double latitude;
  final double longitude;

  const TargetCoordinate({
    required this.latitude,
    required this.longitude,
  });
}

class TargetCoordinateEstimator {
  static const double _earthRadiusMeters = 6371000;

  const TargetCoordinateEstimator();

  TargetCoordinate estimateTargetCoordinate({
    required double latitude,
    required double longitude,
    required double headingDeg,
    required double distanceMeters,
  }) {
    final angularDistance = distanceMeters / _earthRadiusMeters;
    final headingRad = _degreesToRadians(headingDeg);
    final latRad = _degreesToRadians(latitude);
    final lonRad = _degreesToRadians(longitude);

    final targetLatRad = asin(
      sin(latRad) * cos(angularDistance) +
          cos(latRad) * sin(angularDistance) * cos(headingRad),
    );

    final targetLonRad = lonRad +
        atan2(
          sin(headingRad) * sin(angularDistance) * cos(latRad),
          cos(angularDistance) - sin(latRad) * sin(targetLatRad),
        );

    return TargetCoordinate(
      latitude: _radiansToDegrees(targetLatRad),
      longitude: _normalizeLongitude(_radiansToDegrees(targetLonRad)),
    );
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180.0;

  double _radiansToDegrees(double radians) => radians * 180.0 / pi;

  double _normalizeLongitude(double longitude) {
    var normalized = longitude;
    while (normalized < -180) {
      normalized += 360;
    }
    while (normalized > 180) {
      normalized -= 360;
    }
    return normalized;
  }
}
