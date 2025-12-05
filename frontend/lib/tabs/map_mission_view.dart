// lib/tabs/map_mission_view.dart
import 'dart:async';
import 'dart:convert';                         // 👈 jsonEncode

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';

import '../models/facility.dart';
import '../services/facility_api.dart';
import '../screens/mission_route_page.dart';

import 'package:http/http.dart' as http;       // 👈 즐겨찾기 토글용
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';            // apiUri() 사용


class MapMissionView extends StatefulWidget {
  const MapMissionView({super.key});

  @override
  State<MapMissionView> createState() => _MapMissionViewState();
}

class _MapMissionViewState extends State<MapMissionView> {
  NaverMapController? _naverMapController;
  bool _mapReady = false;

  // FastAPI 시설 조회용
  final _facilityApi = FacilityApi();

  bool _loading = true;
  static const NLatLng _defaultCenter = NLatLng(37.5665, 126.9780); // 서울시청
  NLatLng? _userCenter;
  double _radiusKm = 1.0; // 기본 반경 1km

  final Location _location = Location();

  final Completer<NaverMapController> _mapControllerCompleter = Completer();
  NaverMapController? _mapController;

  List<Facility> _facilities = [];
  Facility? _selected;

  // ⭐ 즐겨찾기 (facility_id 집합)
  final Set<int> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _init();                              // 👈 한 번에 초기화
  }

  Future<void> _init() async {
    await _initLocationAndLoad();         // 위치 + 시설 불러오기
    await _loadUserFavorites();           // 로그인 유저 즐겨찾기 불러오기
  }

  NLatLng get _mapCenter => _userCenter ?? _defaultCenter;

  /// 1. 위치 권한 및 현재 위치 가져오기 + 시설 로딩
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
        _userCenter =
            NLatLng(locationData.latitude!, locationData.longitude!);
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

  /// 2. FastAPI에서 시설 데이터 가져오기
  Future<void> _loadFacilities() async {
    setState(() => _loading = true);

    try {
      final center = _mapCenter;
      debugPrint(
          '[MAP] loadFacilities center=${center.latitude},${center.longitude} radius=$_radiusKm');

      final facilities = await _facilityApi.getNearFacilities(
        lat: center.latitude,
        lon: center.longitude,
        radiusKm: _radiusKm,
      );

      if (!mounted) return;

      setState(() {
        _facilities = facilities;
      });

      await _renderOverlays();
    } catch (e) {
      debugPrint('[MAP] 시설 로딩 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('시설 정보를 불러오지 못했어요: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 👇 로그인 유저의 즐겨찾기 목록 불러오기 (/favorites/by-user)
  Future<void> _loadUserFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final uri = apiUri(
        '/favorites/by-user',
        {'user_id': user.id},
      );
      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        debugPrint('[MAP] 즐겨찾기 조회 실패: ${resp.statusCode} ${resp.body}');
        return;
      }

      final List data = jsonDecode(resp.body);
      final ids = <int>{};
      for (final item in data) {
        if (item is Map && item['id'] != null) {
          ids.add(item['id'] as int);
        }
      }

      if (!mounted) return;
      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(ids);
      });
    } catch (e) {
      debugPrint('[MAP] 즐겨찾기 조회 예외: $e');
    }
  }

  /// 👇 즐겨찾기 토글 (/favorites/toggle)
  Future<void> _toggleFavorite(Facility f) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final nowFav = _favoriteIds.contains(f.id);
    final newFav = !nowFav;

    // 1) 먼저 UI 상태 변경
    setState(() {
      if (newFav) {
        _favoriteIds.add(f.id);
      } else {
        _favoriteIds.remove(f.id);
      }
    });

    // 2) 백엔드에 반영
    try {
      final uri = apiUri('/favorites/toggle');
      final body = jsonEncode({
        'user_id': user.id,
        'facility_id': f.id,
        'is_favorite': newFav,
      });

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (resp.statusCode != 200) {
        throw Exception('status=${resp.statusCode}, body=${resp.body}');
      }
    } catch (e) {
      // 실패하면 UI 롤백
      setState(() {
        if (nowFav) {
          _favoriteIds.add(f.id);
        } else {
          _favoriteIds.remove(f.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('즐겨찾기 저장 실패: $e')),
      );
    }
  }

  /// 3. 지도에 마커/반경만 렌더링 (경로는 X)
  Future<void> _renderOverlays() async {
    if (!_mapReady || _naverMapController == null) return;

    final overlays = <NAddableOverlay<NOverlay<void>>>{};

    // 반경 원
    final circle = NCircleOverlay(
      id: 'radius_circle',
      center: _mapCenter,
      radius: _radiusKm * 1000,
      color: const Color.fromARGB(80, 0, 150, 136),
      outlineColor: const Color.fromARGB(180, 0, 150, 136),
      outlineWidth: 2,
    );
    overlays.add(circle);

    // 시설 마커
    for (final f in _facilities) {
      final marker = NMarker(
        id: 'facility_${f.id}',
        position: NLatLng(f.lat, f.lon),
        caption: NOverlayCaption(text: f.name),
      );

      marker.setOnTapListener((overlay) async {
        if (!mounted) return;

        setState(() {
          _selected = f;
        });

        final cameraUpdate = NCameraUpdate.withParams(
          target: NLatLng(f.lat, f.lon),
          zoom: 15,
        );
        await _naverMapController?.updateCamera(cameraUpdate);
      });

      overlays.add(marker);
    }

    await _naverMapController!.clearOverlays();
    await _naverMapController!.addOverlayAll(overlays);

    debugPrint(
        '[MAP] renderOverlays radius=$_radiusKm km, markers=${_facilities.length}');
  }

  /// 리스트에서 아이템 탭 → 지도 포커싱만 (경로 X)
  Future<void> _focusFacility(Facility f) async {
    if (!_mapReady || _naverMapController == null) return;

    setState(() {
      _selected = f;
    });

    final cameraUpdate = NCameraUpdate.withParams(
      target: NLatLng(f.lat, f.lon),
      zoom: 15,
    );
    await _naverMapController!.updateCamera(cameraUpdate);
  }

  /// 미션 3단계 화면으로 이동 (여기에서만 경로 표시)
  void _openMissionPage(Facility f) {
    final start = _userCenter ?? _mapCenter;
    final isFav = _favoriteIds.contains(f.id);     // ⭐ 현재 즐겨찾기 여부

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionRoutePage(
          facility: f,
          startLat: start.latitude,
          startLon: start.longitude,
          isFavorite: isFav,                        // 👈 전달
        ),
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
              _naverMapController = controller;
              _mapReady = true;
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
                        max: 10.0,
                        divisions: 19,
                        activeColor: Colors.teal,
                        onChanged: (val) {
                          setState(() => _radiusKm = val);
                          _renderOverlays(); // 원 크기 즉시 반영
                        },
                        onChangeEnd: (val) {
                          _loadFacilities(); // 반경 값으로 API 다시 호출
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

          // 4. 하단 이지팟 목록 BottomSheet
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.18,
            maxChildSize: 0.6,
            builder: (context, scrollController) {
              if (_facilities.isEmpty) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: const Center(
                    child: Text('반경 내 이지팟 미션이 없습니다.'),
                  ),
                );
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 상단 핸들바
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '이지팟 목록',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _facilities.length,
                        itemBuilder: (context, index) {
                          final f = _facilities[index];
                          final isFav = _favoriteIds.contains(f.id);

                          return ListTile(
                            onTap: () => _focusFacility(f),
                            title: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (f.mission.isNotEmpty)
                                  Text(
                                    f.mission,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 2),
                                Text(
                                  '#${f.category}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isFav
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: isFav
                                        ? Colors.amber
                                        : Colors.grey,
                                  ),
                                  onPressed: () => _toggleFavorite(f),  // 👈 여기!
                                ),
                                TextButton(
                                  onPressed: () => _openMissionPage(f),
                                  child: const Text('미션 시작'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
