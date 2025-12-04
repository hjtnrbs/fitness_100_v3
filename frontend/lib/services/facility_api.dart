// lib/services/facility_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/facility.dart';
import '../config/api_config.dart'; // 🔹 apiUri 사용

class FacilityApi {
  final http.Client _client;

  FacilityApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Facility>> getNearFacilities({
    required double lat,
    required double lon,
    required double radiusKm,
  }) async {
    // 🔹 슬라이더에서 넘어온 radiusKm 그대로 사용
    final uri = apiUri('/facilities/near', {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radius_km': radiusKm.toString(),
    });

    print('[FacilityApi] GET $uri');

    final resp = await _client.get(uri);

    if (resp.statusCode != 200) {
      throw Exception('시설 API 호출 실패: ${resp.statusCode} ${resp.body}');
    }

    final List<dynamic> jsonList = json.decode(resp.body) as List<dynamic>;
    return jsonList
        .map((e) => Facility.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
