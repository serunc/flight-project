import 'dart:convert';
import 'dart:io';
import 'dart:math';

class NearbyFlight {
  final String flightCode;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final DateTime timestamp;

  const NearbyFlight({
    required this.flightCode,
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.timestamp,
  });
}

class FlightService {
  static const String _baseUrl = 'https://opensky-network.org/api/states/all';

  Future<List<NearbyFlight>> fetchNearbyFlights({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    int maxResults = 5,
    double searchRadiusDegrees = 1.0,
  }) async {
    final flights = await _fetchFlightsInBoundingBox(
      minLat: latitude - searchRadiusDegrees,
      minLon: longitude - searchRadiusDegrees,
      maxLat: latitude + searchRadiusDegrees,
      maxLon: longitude + searchRadiusDegrees,
      timestamp: timestamp,
    );

    final withDistance = flights
        .map(
          (flight) => _FlightWithDistance(
            flight: flight,
            distanceMeters: distanceMetersBetween(
              latitude,
              longitude,
              flight.latitude,
              flight.longitude,
            ),
          ),
        )
        .toList();
    withDistance.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return withDistance.take(maxResults).map((item) => item.flight).toList();
  }

  Future<List<NearbyFlight>> fetchFlightsNearCoordinate({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double radiusMeters = 500,
    int maxResults = 30,
  }) async {
    final latitudeDelta = radiusMeters / 111320.0;
    final longitudeDelta = radiusMeters / (111320.0 * cos(_degreesToRadians(latitude)).abs());

    final flights = await _fetchFlightsInBoundingBox(
      minLat: latitude - latitudeDelta,
      minLon: longitude - longitudeDelta,
      maxLat: latitude + latitudeDelta,
      maxLon: longitude + longitudeDelta,
      timestamp: timestamp,
    );

    final withDistance = flights
        .map(
          (flight) => _FlightWithDistance(
            flight: flight,
            distanceMeters: distanceMetersBetween(
              latitude,
              longitude,
              flight.latitude,
              flight.longitude,
            ),
          ),
        )
        .where((item) => item.distanceMeters <= radiusMeters)
        .toList();

    withDistance.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return withDistance.take(maxResults).map((item) => item.flight).toList();
  }

  double distanceMetersBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = (pow(sin(dLat / 2), 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            pow(sin(dLon / 2), 2))
        .toDouble();
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  Future<List<NearbyFlight>> _fetchFlightsInBoundingBox({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required DateTime timestamp,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: <String, String>{
        'lamin': minLat.toStringAsFixed(6),
        'lomin': minLon.toStringAsFixed(6),
        'lamax': maxLat.toStringAsFixed(6),
        'lomax': maxLon.toStringAsFixed(6),
        'time': (timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
      },
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'OpenSky request failed with status: ${response.statusCode}',
          uri: uri,
        );
      }

      final rawBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      final states = (decoded['states'] as List<dynamic>? ?? <dynamic>[]);

      final flights = <NearbyFlight>[];
      for (final state in states) {
        if (state is! List<dynamic>) {
          continue;
        }
        final parsed = _parseFlightState(state);
        if (parsed != null) {
          flights.add(parsed);
        }
      }

      return flights;
    } finally {
      client.close(force: true);
    }
  }

  NearbyFlight? _parseFlightState(List<dynamic> state) {
    final callsign = (state[1] as String?)?.trim();
    final stateLon = _toDouble(state[5]);
    final stateLat = _toDouble(state[6]);
    final baroAltitude = _toDouble(state[7]);
    final geoAltitude = _toDouble(state[13]);
    final timePosition = _toInt(state[3]);
    final lastContact = _toInt(state[4]);

    if (callsign == null || callsign.isEmpty || stateLat == null || stateLon == null) {
      return null;
    }

    final flightTime = DateTime.fromMillisecondsSinceEpoch(
      ((timePosition ?? lastContact ?? 0) * 1000),
      isUtc: true,
    );

    return NearbyFlight(
      flightCode: callsign,
      latitude: stateLat,
      longitude: stateLon,
      altitudeMeters: geoAltitude ?? baroAltitude,
      timestamp: flightTime,
    );
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180.0;

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return null;
  }
}

class _FlightWithDistance {
  final NearbyFlight flight;
  final double distanceMeters;

  const _FlightWithDistance({
    required this.flight,
    required this.distanceMeters,
  });
}
