// 예: lib/pages/map_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/facility_api.dart';
import '../models/facility.dart';

class FacilityMapPage extends StatefulWidget {
  const FacilityMapPage({super.key});

  @override
  State<FacilityMapPage> createState() => _FacilityMapPageState();
}

class _FacilityMapPageState extends State<FacilityMapPage> {
  final _facilityApi = FacilityApi();

  NaverMapController? _mapController;
  List<NMarker> _markers = [];

  // 예시용 시작 위치 (나중에 현재 위치로 교체 가능)
  final NLatLng _initialPos = const NLatLng(37.5665, 126.9780);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('주변 체육시설 지도')),
      body: NaverMap(
        options: NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: _initialPos,
            zoom: 14,
          ),
        ),
        onMapReady: (controller) async {
          _mapController = controller;
          // 지도 준비되면 바로 주변 시설 불러오기
          await _loadFacilities(_initialPos);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (_mapController == null) return;
          final pos = await _mapController!.getCameraPosition();
          await _loadFacilities(pos.target);
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Future<void> _loadFacilities(NLatLng center) async {
    try {
      final facilities = await _facilityApi.getNearFacilities(
        lat: center.latitude,
        lon: center.longitude,
        radiusKm: 2.0,
      );
      print('시설 개수(Flutter): ${facilities.length}');

      // NMarker로 변환
      final markers = facilities.map((f) {
        final marker = NMarker(
          id: 'facility_${f.id}',
          position: NLatLng(f.lat, f.lon),
        );

        marker.setCaption(
          NOverlayCaption(text: f.name),
        );

        return marker;
      }).toList();

      setState(() {
        _markers = markers;
      });

      // 기존 마커 제거 후 새로 올리기
      if (_mapController != null) {
        await _mapController!.clearOverlays();
        _mapController!.addOverlayAll(_markers);
      }
    } catch (e) {
      print('시설 로딩 실패: $e');
    }
  }
}
