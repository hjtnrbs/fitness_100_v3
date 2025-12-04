// lib/pages/facility_map_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/facility_api.dart';

class FacilityMapPage extends StatefulWidget {
  const FacilityMapPage({super.key});

  @override
  State<FacilityMapPage> createState() => _FacilityMapPageState();
}

class _FacilityMapPageState extends State<FacilityMapPage> {
  final _facilityApi = FacilityApi();

  NaverMapController? _mapController;
  List<NMarker> _facilityMarkers = [];
  NMarker? _userMarker;

  bool _isLoading = false;
  String? _infoMessage;
  String? _errorMessage;

  // 🔹 우선 테스트용 시작 위치 (서울시청 근처)
  final NLatLng _initialPos = const NLatLng(37.5665, 126.9780);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주변 공공체육시설'),
      ),
      body: Stack(
        children: [
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _initialPos,
                zoom: 14,
              ),
              locationButtonEnable: true,
            ),
            onMapReady: (controller) async {
              _mapController = controller;
              // 지도 준비되면 초기 위치 기준으로 2km 조회
              await _refreshMarkers(_initialPos);
            },
          ),

          // 🔹 상단 안내 배너 (정보/에러)
          if (_infoMessage != null || _errorMessage != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: _errorMessage != null
                    ? Colors.red.withOpacity(0.9)
                    : Colors.black.withOpacity(0.7),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    _errorMessage ?? _infoMessage ?? '',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),

      // 🔹 현재 카메라 중심 기준으로 다시 조회하는 새로고침 버튼
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_mapController == null) return;
          final cameraPos = await _mapController!.getCameraPosition();
          await _refreshMarkers(cameraPos.target);
        },
        icon: const Icon(Icons.refresh),
        label: const Text('이 위치에서 다시 찾기'),
      ),
    );
  }

  Future<void> _refreshMarkers(NLatLng center) async {
    setState(() {
      _isLoading = true;
      _infoMessage = null;
      _errorMessage = null;
    });

    try {
      // 🔹 2km로 고정
      const double radiusKm = 5.0;

      final facilities = await _facilityApi.getNearFacilities(
        lat: center.latitude,
        lon: center.longitude,
        radiusKm: radiusKm,
      );

      // 디버그 로그
      // ignore: avoid_print
      print('시설 개수(2km): ${facilities.length}');

      // 🔹 사용자 위치 마커
      final userMarker = NMarker(
        id: 'user_location',
        position: center,
      );
      userMarker.setCaption(
        const NOverlayCaption(text: '현재 위치'),
      );

      // 🔹 시설 마커 리스트
      final facilityMarkers = facilities.map((f) {
        final marker = NMarker(
          id: 'facility_${f.id}',
          position: NLatLng(f.lat, f.lon),
        );
        marker.setCaption(
          NOverlayCaption(text: f.name),
        );
        return marker;
      }).toList();

      // 지도에 반영
      if (_mapController != null) {
        await _mapController!.clearOverlays();
        await _mapController!.addOverlay(userMarker);
        if (facilityMarkers.isNotEmpty) {
          await _mapController!.addOverlayAll(facilityMarkers);
        }
      }

      setState(() {
        _userMarker = userMarker;
        _facilityMarkers = facilityMarkers;

        if (facilityMarkers.isEmpty) {
          _infoMessage = '반경 2km 내 공공체육시설이 없어요.\n지도를 이동해서 다시 검색해보세요.';
        } else {
          _infoMessage = null;
        }
      });
    } catch (e) {
      // ignore: avoid_print
      print('시설 조회 실패: $e');
      setState(() {
        _errorMessage = '시설 정보를 불러오는 중 오류가 발생했어요.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
