// lib/config/api_config.dart
const String kApiBaseUrl = 'http://10.0.2.2:8000';  // 에뮬레이터에서 FastAPI

Uri apiUri(String path, [Map<String, String>? query]) {
  return Uri.parse('$kApiBaseUrl$path').replace(queryParameters: query);
}