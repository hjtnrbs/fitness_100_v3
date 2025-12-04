// lib/models/facility.dart
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
