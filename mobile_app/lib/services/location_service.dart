import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentPosition() async {
    print('📍 Location Service: Checking location service status...');
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ Location Service: Location service is disabled');
      throw Exception('Location service kapali.');
    }

    print('🔐 Location Service: Checking location permission...');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      print('🔄 Location Service: Requesting location permission...');
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print('❌ Location Service: Location permission denied');
      throw Exception('Konum izni verilmedi.');
    }

    print('📡 Location Service: Getting current position...');
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    print('✅ Location Service: Position obtained - Lat: ${position.latitude}, Lon: ${position.longitude}, Accuracy: ${position.accuracy}m');
    return position;
  }
}
