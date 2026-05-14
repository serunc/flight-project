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
    print('📸 Capture Metadata Service: Starting capture with metadata...');
    print('🖼️ Image file: ${imageFile.path}');

    final timestamp = DateTime.now();
    print('🕒 Timestamp: $timestamp');

    print('📍 Getting current position...');
    final position = await _locationService.getCurrentPosition();

    print('📐 Getting pitch angle...');
    final pitchAngle = _sensorService.getPitchAngle();

    print('🧭 Getting heading...');
    final headingDeg = _sensorService.getHeadingDeg();

    final captureData = CaptureData(
      imagePath: imageFile.path,
      timestamp: timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      pitchAngle: pitchAngle,
      headingDeg: headingDeg,
      orientation: orientation,
    );

    print('✅ Capture Metadata Service: Capture completed');
    print('📊 Final data: Lat=${position.latitude.toStringAsFixed(6)}, Lon=${position.longitude.toStringAsFixed(6)}, Pitch=${pitchAngle.toStringAsFixed(2)}°, Heading=${headingDeg?.toStringAsFixed(2) ?? 'N/A'}°, Orientation=$orientation');

    return captureData;
  }
}
