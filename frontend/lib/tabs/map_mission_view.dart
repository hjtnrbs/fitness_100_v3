// lib/tabs/map_mission_view.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';
import '../models/facility.dart';   // 🔹 이 줄 추가

import '../services/facility_api.dart'; // FastAPI 연동
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart'; // 이미 있으면 생략

class MapMissionView extends StatefulWidget {
  const MapMissionView({super.key});

  @override
  State<MapMissionView> createState() => _MapMissionViewState();
}

class _MapMissionViewState extends State<MapMissionView> {
  NaverMapController? _naverMapController;
  bool _mapReady = false;
  // 🔹 FastAPI 시설 조회용
  final _facilityApi = FacilityApi();

  // 상태 변수
  bool _loading = true;
  static const NLatLng _defaultCenter = NLatLng(37.5665, 126.9780); // 서울시청
  NLatLng? _userCenter;
  double _radiusKm = 1.0; // 기본 반경 1km

  // 지도 컨트롤러
  NaverMapController? _mapController;
  final Completer<NaverMapController> _mapControllerCompleter = Completer();

  // 데이터
  List<Facility> _facilities = [];
  Facility? _selected; // 선택된 시설

  // 위치 서비스
  final Location _location = Location();
  // ✅ 추가: 길찾기 polyline
  NPathOverlay? _routePath;

  @override
  void initState() {
    super.initState();
    _initLocationAndLoad();
  }

  NLatLng get _mapCenter => _userCenter ?? _defaultCenter;

  // 1. 위치 권한 및 현재 위치 가져오기
  Future<void> _initLocationAndLoad() async {
    try {
      bool serviceEnabled;
      PermissionStatus permissionGranted;

      serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          _userCenter = _defaultCenter;
          await _loadFacilities();
          return;
        }
      }

      permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          _userCenter = _defaultCenter;
          await _loadFacilities();
          return;
        }
      }

      final locationData = await _location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _userCenter = NLatLng(locationData.latitude!, locationData.longitude!);
      } else {
        _userCenter = _defaultCenter;
      }

      await _loadFacilities();
    } catch (e) {
      debugPrint("[MAP] 위치 초기화 오류: $e");
      _userCenter ??= _defaultCenter;
      await _loadFacilities();
    }
  }

  // 2. FastAPI에서 시설 데이터 가져오기
  Future<void> _loadFacilities() async {
    setState(() => _loading = true);

    try {
      final center = _mapCenter;

      print('[MAP] loadFacilities center=${center.latitude},${center.longitude} radius=$_radiusKm');

      // ✅ 슬라이더 값(_radiusKm) 그대로 사용
      final facilities = await _facilityApi.getNearFacilities(
        lat: center.latitude,
        lon: center.longitude,
        radiusKm: _radiusKm,
      );

      if (!mounted) return;

      setState(() {
        _facilities = facilities;
        // ✅ 여기에서 _radiusKm를 10.0 같은 값으로 덮어쓰지 않는다
      });

      await _renderOverlays();
    } catch (e) {
      print('[MAP] 시설 로딩 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('시설 정보를 불러오지 못했어요: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 네이버 Directions를 FastAPI를 통해 호출해서
  // 내 위치 -> 시설까지 도로 경로 polyline 생성
  Future<void> _loadRoute(Facility facility) async {
    // 시작점: 사용자 위치 없으면 현재 지도 중심
    final start = _userCenter ?? _mapCenter;

    try {
      final uri = apiUri('/route', {
        'start_lat': start.latitude.toString(),
        'start_lon': start.longitude.toString(),
        'end_lat': facility.lat.toString(),
        'end_lon': facility.lon.toString(),
      });

      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('경로 API 실패: ${resp.statusCode} ${resp.body}');
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final List<dynamic> path = data['path'] as List<dynamic>;

      // [[lon,lat], ...] → List<NLatLng>
      final coords = path
          .map<NLatLng>((p) => NLatLng(
                (p[1] as num).toDouble(),
                (p[0] as num).toDouble(),
              ))
          .toList();

      final routeOverlay = NPathOverlay(
        id: 'naver_route',
        coords: coords,
        width: 6,
        color: const Color.fromARGB(220, 0, 150, 136),
      );

      if (!mounted) return;
      setState(() {
        _routePath = routeOverlay;
      });

      await _renderOverlays();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('경로 정보를 불러오지 못했어요: $e')),
      );
    }
  }


  // 3. 지도에 마커 및 반경 원 그리기
  Future<void> _renderOverlays() async {
    if (!_mapReady) return;

    final overlays = <NAddableOverlay<NOverlay<void>>>{};

    // 1) 반경 원
    final circle = NCircleOverlay(
      id: 'radius_circle',
      center: _mapCenter,
      radius: _radiusKm * 1000,
      color: const Color.fromARGB(80, 0, 150, 136),
      outlineColor: const Color.fromARGB(180, 0, 150, 136),
      outlineWidth: 2,
    );
    overlays.add(circle);

    // 2) 시설 마커들
    for (final f in _facilities) {
      final marker = NMarker(
        id: 'facility_${f.id}',
        position: NLatLng(f.lat, f.lon),
        caption: NOverlayCaption(text: f.name),
      );

      // 마커 탭 → 선택 + 경로 로드
      marker.setOnTapListener((overlay) async {
        if (!mounted) return;

        setState(() {
          _selected = f;
          _routePath = null; // 새 경로로 교체 예정
        });

        // 카메라를 선택 시설로 조금 이동
        final cameraUpdate = NCameraUpdate.withParams(
          target: NLatLng(f.lat, f.lon),
          zoom: 15,
        );
        await _naverMapController?.updateCamera(cameraUpdate);

        // 네이버 Directions 호출
        await _loadRoute(f);
      });

      overlays.add(marker);
    }

    // 3) 경로 polyline 있으면 추가
    if (_routePath != null) {
      overlays.add(_routePath!);
    }

    await _naverMapController?.clearOverlays();
    await _naverMapController?.addOverlayAll(overlays);

    print('[MAP] renderOverlays radius=$_radiusKm km, markers=${_facilities.length}');
  }



  // (참고용) 거리 계산 – 지금은 FastAPI가 이미 반경 필터링해줘서 사용 안 함
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double v) => v * math.pi / 180.0;

    Future<void> _openRoute() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 지도에서 시설을 선택해 주세요.')),
      );
      return;
    }

    // 출발점: 사용자 위치(없으면 현재 지도 중심)
    final start = _userCenter ?? _mapCenter;
    final dest = _selected!;
    final destName = Uri.encodeComponent(dest.name);

    // 🔹 1. 네이버 지도 앱용 딥링크 (도보 길찾기 예시)
    final naverAppUri = Uri.parse(
      'nmap://route/walk'
      '?slat=${start.latitude}&slng=${start.longitude}' // 출발
      '&dlat=${dest.lat}&dlng=${dest.lon}'              // 도착
      '&dname=$destName'
      '&appname=com.example.lowageapp',                // ← 패키지명으로 수정해도 됨
    );

    // 🔹 2. 앱이 없을 때를 위한 웹 URL (브라우저로 열기)
    final naverWebUri = Uri.parse(
      'https://map.naver.com/v5/directions/'
      '${start.longitude},${start.latitude},출발지,,/'
      '${dest.lon},${dest.lat},$destName,,',
    );

    try {
      if (await canLaunchUrl(naverAppUri)) {
        await launchUrl(naverAppUri);
      } else {
        await launchUrl(
          naverWebUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('경로 안내를 열 수 없어요: $e')),
      );
    }
  }


  // 4. 미션 시작 (지금은 라우팅/로그 없이 안내만)
  void _startMission() {
    if (_selected == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('미션/경로 안내는 추후 연동 예정입니다.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 네이버 지도
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _mapCenter,
                zoom: 14,
              ),
              locationButtonEnable: true,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) async {
              _naverMapController = controller;  // ✅ 컨트롤러 저장
              _mapReady = true;                  // ✅ 준비 완료 표시
              await _renderOverlays();           // 첫 렌더링
              _mapController = controller;
              if (!_mapControllerCompleter.isCompleted) {
                _mapControllerCompleter.complete(controller);
              }

              // 사용자 위치로 카메라 이동
              if (_userCenter != null) {
                final cameraUpdate = NCameraUpdate.withParams(
                  target: _userCenter!,
                  zoom: 14,
                );
                await controller.updateCamera(cameraUpdate);
              }

              await _renderOverlays();
            },
          ),

          // 2. 상단 반경 설정 카드
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.radar, color: Colors.teal),
                    const SizedBox(width: 12),
                    Text(
                      "반경 ${_radiusKm.toStringAsFixed(1)}km",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _radiusKm,
                        min: 0.5,
                        max: 10.0,         // 0.5 ~ 10km
                        divisions: 19,    // 0.5km 단위
                        activeColor: Colors.teal,
                        onChanged: (val) {
                          setState(() => _radiusKm = val);
                          _renderOverlays(); // 원 크기 즉시 갱신
                        },
                        onChangeEnd: (val) {
                          _loadFacilities(); // 반경 바뀐 값으로 API 다시 호출
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. 로딩 인디케이터
          if (_loading) const Center(child: CircularProgressIndicator()),

          // 4. 하단 시설 정보 패널 (마커 선택 시 표시)
          if (_selected != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selected!.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => setState(() => _selected = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selected!.mission,
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#${_selected!.category}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _openRoute,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "미션 시작 / 경로 안내 (준비중)",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
