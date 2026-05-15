import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class Fr24Service {
  final String baseUrl = 'https://fr24api.flightradar24.com/api';

  Future<List<Map<String, dynamic>>> getNearbyFlights({
    required double lat,
    required double lon,
    double radiusMeters = 50000,
  }) async {
    final token = dotenv.env['FR24_API_TOKEN'];

    if (token == null || token.isEmpty) {
      throw Exception('FR24 token bulunamadı');
    }

    final bounds = _makeBounds(lat, lon, radiusMeters);

    final uri = Uri.parse(
      '$baseUrl/live/flight-positions/full',
    ).replace(queryParameters: {'bounds': bounds});

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Accept-Version': 'v1',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'FR24 API hatası: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is List) {
      return List<Map<String, dynamic>>.from(decoded);
    }

    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is List) {
        return List<Map<String, dynamic>>.from(decoded['data']);
      }
      if (decoded['positions'] is List) {
        return List<Map<String, dynamic>>.from(decoded['positions']);
      }
      if (decoded['flights'] is List) {
        return List<Map<String, dynamic>>.from(decoded['flights']);
      }
    }

    throw Exception(
      'FR24 API yanıtı beklenmeyen biçimde: ${decoded.runtimeType}',
    );
  }

  String _makeBounds(double lat, double lon, double radiusMeters) {
    final delta = radiusMeters / 111000;

    final north = lat + delta;
    final south = lat - delta;
    final west = lon - delta;
    final east = lon + delta;

    return '$north,$south,$west,$east';
  }
}
