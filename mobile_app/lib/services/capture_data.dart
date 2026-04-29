class CaptureData {
  final String imagePath;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double pitchAngle;
  final double? headingDeg;
  final String orientation;

  const CaptureData({
    required this.imagePath,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.pitchAngle,
    required this.headingDeg,
    required this.orientation,
  });
}
