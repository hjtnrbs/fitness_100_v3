// lib/services/physical_age_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class PhysicalAgeResult {
  // 🔹 백엔드 응답 필드 매핑
  final double loAgeValue;      // lo_age_value (숫자 신체나이)
  final String gradeLabel;      // lo_age_tier_label 또는 grade_label
  final double percentile;      // percentile (0~100)
  final String weakPoint;       // "cardio_endurance" 등
  final int tierIndex;          // tier_index (0~16)

  PhysicalAgeResult({
    required this.loAgeValue,
    required this.gradeLabel,
    required this.percentile,
    required this.weakPoint,
    required this.tierIndex,
  });

  factory PhysicalAgeResult.fromJson(Map<String, dynamic> json) {
    return PhysicalAgeResult(
      loAgeValue: (json['lo_age_value'] as num).toDouble(),
      gradeLabel: (json['lo_age_tier_label'] ?? json['grade_label']) as String,
      percentile: (json['percentile'] as num).toDouble(),
      weakPoint: json['weak_point'] as String,
      tierIndex: (json['tier_index'] as num).toInt(),
    );
  }
}

/// 히스토리 한 건
class PhysicalAgeHistoryRecord {
  final int id;
  final String userId;
  final DateTime measuredAt;
  final int gradeIndex;
  final String gradeLabel;
  final double percentile;
  final String? weakPoint;
  final double? avgQuantile;

  PhysicalAgeHistoryRecord({
    required this.id,
    required this.userId,
    required this.measuredAt,
    required this.gradeIndex,
    required this.gradeLabel,
    required this.percentile,
    this.weakPoint,
    this.avgQuantile,
  });

  factory PhysicalAgeHistoryRecord.fromJson(Map<String, dynamic> json) {
    return PhysicalAgeHistoryRecord(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      measuredAt: DateTime.parse(json['measured_at'] as String),
      gradeIndex: (json['grade_index'] as num).toInt(),
      gradeLabel: json['grade_label'] as String,
      percentile: (json['percentile'] as num).toDouble(),
      weakPoint: json['weak_point'] as String?,
      avgQuantile: json['avg_quantile'] == null
          ? null
          : (json['avg_quantile'] as num).toDouble(),
    );
  }
}

class PhysicalAgeApi {
  /// 신체나이 예측
  Future<PhysicalAgeResult> predictPhysicalAge({
    String? userId,                 // 👈 nullable 로 변경
    required String sex,            // 'M' / 'F'
    required double sitUps,         // 👈 전부 double 로 변경
    required double flexibility,
    required double jumpPower,
    required double cardioEndurance,
  }) async {
    final uri = apiUri('/predict/physical-age');

    final body = jsonEncode({
      'user_id': userId,            // null 이어도 그대로 전송
      'sex': sex,
      'sit_ups': sitUps,
      'flexibility': flexibility,
      'jump_power': jumpPower,
      'cardio_endurance': cardioEndurance,
    });

    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('신체나이 API 실패: ${res.statusCode} / ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    final Map<String, dynamic> data =
        decoded is List ? (decoded.first as Map<String, dynamic>)
                        : (decoded as Map<String, dynamic>);

    return PhysicalAgeResult.fromJson(data);
  }

  /// 신체나이 히스토리 조회
  Future<List<PhysicalAgeHistoryRecord>> fetchHistory(
    String userId, {
    int limit = 20,
  }) async {
    final uri = apiUri('/users/$userId/physical-age/history')
        .replace(queryParameters: {'limit': '$limit'});

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception(
          '신체나이 히스토리 API 실패: ${res.statusCode} / ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> recordsJson = decoded['records'] as List<dynamic>;

    return recordsJson
        .map((e) =>
            PhysicalAgeHistoryRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
