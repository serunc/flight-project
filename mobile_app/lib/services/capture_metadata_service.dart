import 'package:camera/camera.dart';

import 'capture_data.dart';
import 'location_service.dart';
import 'sensor_service.dart';

class CaptureMetadataService {
  CaptureMetadataService({
    required LocationService locationService,
    required SensorService sensorService,
  })  : _locationService = locationService,
        _sensorService = sensorService;

  final LocationService _locationService;
  final SensorService _sensorService;

  Future<CaptureData> captureWithMetadata(
    XFile imageFile, {
    required String orientation,
  }) async {
    final timestamp = DateTime.now();
    final position = await _locationService.getCurrentPosition();
    final pitchAngle = _sensorService.getPitchAngle();
    final headingDeg = _sensorService.getHeadingDeg();

    return CaptureData(
      imagePath: imageFile.path,
      timestamp: timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      pitchAngle: pitchAngle,
      headingDeg: headingDeg,
      orientation: orientation,
    );
  }
}
