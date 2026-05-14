import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'services/aircraft_position_estimator.dart';
import 'services/capture_data.dart';
import 'services/capture_metadata_service.dart';
import 'services/flight_service.dart';
import 'services/location_service.dart';
import 'services/sensor_service.dart';
import 'services/target_coordinate_estimator.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  CaptureData? _captureData;
  TargetCoordinate? _targetCoordinate;
  NearbyFlight? _detectedFlight;
  List<NearbyFlight> _otherNearbyFlights = <NearbyFlight>[];
  double? _estimatedDistanceMeters;
  double? _userAircraftDistanceMeters;
  bool _isTakingPhoto = false;
  late final AircraftPositionEstimator _aircraftPositionEstimator;
  late final TargetCoordinateEstimator _targetCoordinateEstimator;
  late final FlightService _flightService;
  late final SensorService _sensorService;
  late final CaptureMetadataService _captureMetadataService;

  @override
  void initState() {
    super.initState();
    _aircraftPositionEstimator = const AircraftPositionEstimator();
    _targetCoordinateEstimator = const TargetCoordinateEstimator();
    _flightService = FlightService();
    _sensorService = SensorService()..start();
    _captureMetadataService = CaptureMetadataService(
      locationService: LocationService(),
      sensorService: _sensorService,
    );
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kamera bulunamadi.')));
      return;
    }

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    setState(() {
      _controller = controller;
      _initializeControllerFuture = controller.initialize();
    });
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    final initializeFuture = _initializeControllerFuture;

    if (controller == null || initializeFuture == null || _isTakingPhoto) {
      return;
    }

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      print('📷 Camera Screen: Taking picture...');
      await initializeFuture;

      final orientation =
          MediaQuery.of(context).orientation == Orientation.portrait
          ? 'portrait'
          : 'landscape';
      print('📱 Camera Screen: Device orientation: $orientation');

      final XFile file = await controller.takePicture();
      print('✅ Camera Screen: Picture taken, file: ${file.path}');

      print('🔄 Camera Screen: Processing capture metadata...');
      final captureData = await _captureMetadataService.captureWithMetadata(
        file,
        orientation: orientation,
      );

      if (!mounted) {
        print('⚠️ Camera Screen: Widget not mounted after capture');
        return;
      }

      print(
        '🚀 Camera Screen: Processing capture data for flight detection...',
      );
      await _processCaptureData(captureData);
      print('✅ Camera Screen: Capture process completed successfully');
    } catch (error) {
      print('❌ Camera Screen: Error during capture: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fotoğraf çekilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  Future<void> _processCaptureData(CaptureData captureData) async {
    final headingDeg = captureData.headingDeg;
    if (headingDeg == null) {
      setState(() {
        _captureData = captureData;
        _estimatedDistanceMeters = null;
        _targetCoordinate = null;
        _detectedFlight = null;
        _otherNearbyFlights = <NearbyFlight>[];
        _userAircraftDistanceMeters = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yön bilgisi alınamadı')));
      return;
    }

    final estimatedDistanceMeters = _aircraftPositionEstimator
        .estimateDistanceMeters(
          pitchAngleDeg: captureData.pitchAngle,
          estimatedAltitudeMeters: 10000,
        );
    if (estimatedDistanceMeters == null) {
      setState(() {
        _captureData = captureData;
        _estimatedDistanceMeters = null;
        _targetCoordinate = null;
        _detectedFlight = null;
        _otherNearbyFlights = <NearbyFlight>[];
        _userAircraftDistanceMeters = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Açı bilgisi yeterli değil')),
      );
      return;
    }

    final targetCoordinate = _targetCoordinateEstimator
        .estimateTargetCoordinate(
          latitude: captureData.latitude,
          longitude: captureData.longitude,
          headingDeg: headingDeg,
          distanceMeters: estimatedDistanceMeters,
        );

    print(
      '🎯 Target coordinate: lat=${targetCoordinate.latitude.toStringAsFixed(6)}, lon=${targetCoordinate.longitude.toStringAsFixed(6)}',
    );
    print(
      '📏 Estimated distance to aircraft: ${estimatedDistanceMeters.toStringAsFixed(2)} meters',
    );

    // sabiha gokcen havalimanı koordinatları: 40.8986, 29.3092
    const bool useTestLocation = true;
    final latitude = useTestLocation ? 40.8986 : targetCoordinate.latitude;
    final longitude = useTestLocation ? 29.3092 : targetCoordinate.longitude;

    final candidateFlights = await _flightService.fetchNearbyFlights(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      maxResults: 10,
      searchRadiusDegrees: 1.0, // ~500 meters
    );

    NearbyFlight? detectedFlight;
    final otherNearbyFlights = <NearbyFlight>[];
    double? userAircraftDistanceMeters;

    print('✈️ Candidate flights found: ${candidateFlights.length}');

    if (candidateFlights.isNotEmpty) {
      detectedFlight = candidateFlights.first;
      print(
        '✈️ Detected flight: ${detectedFlight.flightCode} at ${detectedFlight.latitude.toStringAsFixed(6)}, ${detectedFlight.longitude.toStringAsFixed(6)}, alt=${detectedFlight.altitudeMeters?.toStringAsFixed(0) ?? 'unknown'}',
      );

      for (final flight in candidateFlights.skip(1)) {
        final distanceToDetected = _flightService.distanceMetersBetween(
          detectedFlight.latitude,
          detectedFlight.longitude,
          flight.latitude,
          flight.longitude,
        );
        if (distanceToDetected <= 500) {
          otherNearbyFlights.add(flight);
        }
      }

      final horizontalDistance = _flightService.distanceMetersBetween(
        captureData.latitude,
        captureData.longitude,
        detectedFlight.latitude,
        detectedFlight.longitude,
      );
      final altitudeMeters = detectedFlight.altitudeMeters ?? 10000;
      userAircraftDistanceMeters = sqrt(
        horizontalDistance * horizontalDistance +
            altitudeMeters * altitudeMeters,
      );
      print(
        '📏 User to aircraft 3D distance: ${userAircraftDistanceMeters.toStringAsFixed(2)} meters',
      );
    } else {
      print('⚠️ Processing: No flights found near target coordinate');
    }

    print('✅ Processing completed. Updating UI...');
    setState(() {
      _captureData = captureData;
      _estimatedDistanceMeters = estimatedDistanceMeters;
      _targetCoordinate = targetCoordinate;
      _detectedFlight = detectedFlight;
      _otherNearbyFlights = otherNearbyFlights;
      _userAircraftDistanceMeters = userAircraftDistanceMeters;
    });
  }

  @override
  void dispose() {
    _sensorService.stop();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initializeFuture = _initializeControllerFuture;

    return Scaffold(
      appBar: AppBar(title: const Text('Kamera')),
      body: Column(
        children: [
          Expanded(
            child: initializeFuture == null
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<void>(
                    future: initializeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          _controller != null) {
                        return CameraPreview(_controller!);
                      }
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _isTakingPhoto ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Fotoğraf Çek'),
                ),
                const SizedBox(height: 12),
                Text(
                  _captureData == null
                      ? 'Henüz fotoğraf çekilmedi.'
                      : _buildInfoText(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildInfoText() {
    final data = _captureData;
    if (data == null) {
      return 'Henüz fotoğraf çekilmedi.';
    }

    return [
      '1) Fotoğraf bilgileri',
      'Path: ${data.imagePath}',
      'Timestamp: ${data.timestamp.toIso8601String()}',
      'Latitude: ${data.latitude}',
      'Longitude: ${data.longitude}',
      'Pitch: ${data.pitchAngle.toStringAsFixed(2)}°',
      'Heading: ${data.headingDeg?.toStringAsFixed(2) ?? 'yok'}°',
      'Orientation: ${data.orientation}',
      'Tahmini yatay uzaklık: '
          '${_estimatedDistanceMeters?.toStringAsFixed(2) ?? 'hesaplanamadi'} metre',
      '',
      '2) Tahmini hedef koordinat',
      'Latitude: ${_targetCoordinate?.latitude.toStringAsFixed(6) ?? 'hesaplanamadi'}',
      'Longitude: ${_targetCoordinate?.longitude.toStringAsFixed(6) ?? 'hesaplanamadi'}',
      '',
      '3) Tespit edilen uçak',
      _detectedFlight == null
          ? 'Uçak tespit edilemedi.'
          : '${_detectedFlight!.flightCode} '
                '(${_detectedFlight!.latitude.toStringAsFixed(6)}, '
                '${_detectedFlight!.longitude.toStringAsFixed(6)}) '
                'altitude: ${_detectedFlight!.altitudeMeters?.toStringAsFixed(2) ?? '10000 varsayildi'} m',
      '',
      '4) Kullanıcı-uçak mesafesi',
      '${_userAircraftDistanceMeters?.toStringAsFixed(2) ?? 'hesaplanamadi'} metre',
      '',
      '5) Yakındaki diğer uçaklar',
      if (_otherNearbyFlights.isEmpty)
        'Yok'
      else
        ..._otherNearbyFlights.map(
          (flight) =>
              '- ${flight.flightCode} '
              '(${flight.latitude.toStringAsFixed(6)}, '
              '${flight.longitude.toStringAsFixed(6)})',
        ),
    ].join('\n');
  }
}
