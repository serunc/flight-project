import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import 'services/fr24_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;

  bool _loading = true;
  bool _scanning = false;

  String? _error;
  File? _photo;

  double? _heading;

  List<Map<String, dynamic>> _flights = [];
  Map<String, dynamic>? _selectedFlight;

  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _initCamera();
    _listenCompass();
  }

  void _showAllFlightsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        if (_flights.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Henüz uçak taranmadı.',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _flights.length,
          itemBuilder: (context, index) {
            final f = _flights[index];

            final flightCode = f['callsign'] ?? f['flight'] ?? 'Bilinmiyor';
            final aircraftType =
                f['type'] ?? f['aircraft_code'] ?? 'Bilinmiyor';
            final model = f['model'] ?? f['aircraft_model'] ?? aircraftType;
            final departure =
                f['orig_iata'] ?? f['orig_icao'] ?? f['origin'] ?? 'Bilinmiyor';
            final arrival =
                f['dest_iata'] ??
                f['dest_icao'] ??
                f['destination'] ??
                'Bilinmiyor';

            return Card(
              color: Colors.greenAccent.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.greenAccent),
              ),
              child: ListTile(
                leading: const Icon(Icons.flight, color: Colors.greenAccent),
                title: Text(
                  '$flightCode',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Tür: $aircraftType\n'
                  'Model: $model\n'
                  'Kalkış: $departure\n'
                  'İniş: $arrival',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _listenCompass() {
    FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        _heading = event.heading;
      });
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Kamera açılamadı: $e';
        _loading = false;
      });
    }
  }

  Future<void> _scanAircraft() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _scanning = true;
      _error = null;
      _selectedFlight = null;
      _flights = [];
    });

    try {
      final image = await _controller!.takePicture();
      _photo = File(image.path);

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Konum izni verilmedi');
      }

      const sawLat = 40.8986;
      const sawLon = 29.3092;

      final flights = await Fr24Service().getNearbyFlights(
        lat: sawLat,
        lon: sawLon,
        radiusMeters: 20000,
      );

      final selected = findBestFlightByHeading(
        flights: flights,
        userLat: sawLat,
        userLon: sawLon,
        heading: _heading ?? 0,
      );

      if (!mounted) return;

      setState(() {
        _flights = flights;
        _selectedFlight =
            selected ?? (flights.isNotEmpty ? flights.first : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _scanning = false;
      });
    }
  }

  Map<String, dynamic>? findBestFlightByHeading({
    required List<Map<String, dynamic>> flights,
    required double userLat,
    required double userLon,
    required double heading,
  }) {
    Map<String, dynamic>? bestFlight;
    double bestDiff = 999;

    for (final flight in flights) {
      final flightLat = flight['lat'];
      final flightLon = flight['lon'];

      if (flightLat == null || flightLon == null) continue;

      final bearing = calculateBearing(
        userLat,
        userLon,
        (flightLat as num).toDouble(),
        (flightLon as num).toDouble(),
      );

      final diff = angleDifference(heading, bearing);

      if (diff < bestDiff) {
        bestDiff = diff;
        bestFlight = flight;
      }
    }

    return bestFlight;
  }

  double calculateBearing(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    final lat1 = startLat * pi / 180;
    final lat2 = endLat * pi / 180;
    final dLon = (endLon - startLon) * pi / 180;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360;
  }

  double angleDifference(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    if (_error != null && _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _photo == null
              ? CameraPreview(_controller!)
              : Image.file(_photo!, fit: BoxFit.cover),

          Container(color: Colors.black.withOpacity(0.18)),

          _buildTopHud(),

          _buildTargetBox(),

          if (_scanning) _buildScanningEffect(),

          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    return Positioned(
      top: 55,
      left: 18,
      right: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _hudBox(icon: Icons.auto_awesome, text: 'AI'),
          GestureDetector(
            onTap: _showAllFlightsSheet,
            child: _hudBox(
              icon: Icons.flight,
              text: '${_flights.length} AIRCRAFT',
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudBox({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetBox() {
    return const Center(
      child: CustomPaint(
        size: Size(260, 260),
        painter: AircraftTargetPainter(),
      ),
    );
  }

  Widget _buildScanningEffect() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Positioned(
          top:
              MediaQuery.of(context).size.height *
              (0.25 + _scanController.value * 0.35),
          left: 40,
          right: 40,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.9),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: 35,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedFlight != null) _buildResultCard(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _scanning ? null : _scanAircraft,
                icon: Icon(_scanning ? Icons.radar : Icons.camera_alt),
                label: Text(
                  _scanning ? 'SCANNING...' : 'SCAN AIRCRAFT',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final f = _selectedFlight!;

    final flightCode = f['callsign'] ?? f['flight'] ?? 'Bilinmiyor';
    final aircraftType = f['type'] ?? f['aircraft_code'] ?? 'Bilinmiyor';
    final model = f['model'] ?? f['aircraft_model'] ?? aircraftType;

    final departure = f['orig_iata'] ?? f['orig_icao'] ?? f['origin'] ?? '---';

    final arrival =
        f['dest_iata'] ?? f['dest_icao'] ?? f['destination'] ?? '---';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.22),
              width: 1.4,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.18),
                Colors.white.withOpacity(0.04),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TARGET LOCKED',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$flightCode',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _routeColumn(
                    code: '$departure',
                    label: 'Kalkış',
                    alignEnd: false,
                  ),
                  const Icon(
                    Icons.flight_takeoff,
                    color: Colors.white70,
                    size: 30,
                  ),
                  _routeColumn(code: '$arrival', label: 'İniş', alignEnd: true),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(color: Colors.white24),
              const SizedBox(height: 10),

              _detailLine('Uçak Türü', '$aircraftType'),
              _detailLine('Model', '$model'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeColumn({
    required String code,
    required String label,
    required bool alignEnd,
  }) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13),
        ),
      ],
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AircraftTargetPainter extends CustomPainter {
  const AircraftTargetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Ortadaki ufak yuvarlak
    canvas.drawCircle(center, radius * 0.15, paint);

    // Yatay çizgiler (Ortayı boş bırakacak şekilde)
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(center.dx - 25, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + 25, center.dy),
      Offset(size.width, center.dy),
      paint,
    );

    // Dikey çizgiler (Ortayı boş bırakacak şekilde)
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, center.dy - 25),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + 25),
      Offset(center.dx, size.height),
      paint,
    );

    // İsteğe bağlı ince köşelikler
    const double cornerSize = 20.0;

    // Sol üst
    canvas.drawLine(Offset(0, 0), Offset(cornerSize, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(0, cornerSize), paint);
    // Sağ üst
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerSize, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerSize),
      paint,
    );
    // Sol alt
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerSize, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerSize),
      paint,
    );
    // Sağ alt
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerSize, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerSize),
      paint,
    );

    // Neon glow efekti eklemek için
    final glowPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.4)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawCircle(center, radius * 0.15, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
