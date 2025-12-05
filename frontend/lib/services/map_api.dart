// lib/services/map_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const String baseUrl = 'http://10.0.2.2:8000';

class Facility {
  final int id;
  final String name;
  final double lat;
  final double lon;
  final String address;
  final String mission;
  final String category;

  Facility({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.address,
    required this.mission,
    required this.category,
  });

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'] as int,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      address: json['address'] as String? ?? '',
      mission: json['mission'] as String? ?? '',
      category: json['category'] as String? ?? '',
    );
  }
}

class MapApi {
  /// 반경 내 시설 리스트 조회
  static Future<List<Facility>> getNearFacilities({
    required double lat,
    required double lon,
    double radiusKm = 2.0,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/facilities/near?lat=$lat&lon=$lon&radius_km=$radiusKm',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('시설 조회 실패: ${res.statusCode} ${res.body}');
    }

    final List<dynamic> data = jsonDecode(res.body);
    return data.map((e) => Facility.fromJson(e)).toList();
  }

  /// 네이버 길찾기 경로 호출 -> [[lon,lat], ...] 좌표 리스트 반환
  static Future<List<List<double>>> getRoutePath({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route?start_lat=$startLat&start_lon=$startLon&end_lat=$endLat&end_lon=$endLon',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('경로 조회 실패: ${res.statusCode} ${res.body}');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final List<dynamic> rawPath = data['path'] ?? [];
    return rawPath
        .map<List<double>>((e) => [
              (e[0] as num).toDouble(), // lon
              (e[1] as num).toDouble(), // lat
            ])
        .toList();
  }
}
