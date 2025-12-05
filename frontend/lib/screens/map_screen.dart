// lib/screens/map_screen.dart
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/map_api.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  NaverMapController? _mapController;

  // 테스트용 시작 위치 (서울시청 근처)
  static const NLatLng _startLatLng = NLatLng(37.5665, 126.9780);

  final List<Facility> _facilities = [];
  final Set<NMarker> _markers = {};
  NPathOverlay? _routeOverlay;

  bool _isLoadingFacilities = false;
  bool _isLoadingRoute = false;

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('공공체육시설 지도'),
      ),
      body: Stack(
        children: [
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: const NCameraPosition(
                target: _startLatLng,
                zoom: 14,
              ),
              contentPadding: safePadding,
              locationButtonEnable: true,
            ),
            onMapReady: (controller) async {
              log('[MAP] onMapReady');
              _mapController = controller;
              await _loadFacilities();
            },
          ),

          if (_isLoadingFacilities || _isLoadingRoute)
            const Positioned(
              top: 16,
              right: 16,
              child: CircularProgressIndicator(),
            ),

          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _facilities.isEmpty ? null : _drawRouteToFirstFacility,
              label: const Text('첫 시설까지 경로'),
              icon: const Icon(Icons.route),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFacilities() async {
    if (_mapController == null) return;

    setState(() {
      _isLoadingFacilities = true;
    });

    try {
      final list = await MapApi.getNearFacilities(
        lat: _startLatLng.latitude,
        lon: _startLatLng.longitude,
        radiusKm: 2.0,
      );

      _facilities
        ..clear()
        ..addAll(list);

      _markers.clear();

      for (final f in _facilities) {
        final marker = NMarker(
          id: 'facility_${f.id}',
          position: NLatLng(f.lat, f.lon),
          caption: NOverlayCaption(text: f.name),
        );

        marker.setOnTapListener((overlay) {
          _drawRouteToFacility(f);
          return true;
        });

        _markers.add(marker);
      }

      _mapController!.addOverlayAll(_markers);
      log('[MAP] 시설 ${_facilities.length}개 마커 추가');
    } catch (e, st) {
      log('[MAP] 시설 로딩 실패: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('시설 로딩 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFacilities = false;
        });
      }
    }
  }

  Future<void> _drawRouteToFirstFacility() async {
    if (_facilities.isEmpty) return;
    await _drawRouteToFacility(_facilities.first);
  }

  Future<void> _drawRouteToFacility(Facility facility) async {
    if (_mapController == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final pathLonLat = await MapApi.getRoutePath(
        startLat: _startLatLng.latitude,
        startLon: _startLatLng.longitude,
        endLat: facility.lat,
        endLon: facility.lon,
      );

      final coords = pathLonLat
          .map(
            (e) => NLatLng(
              e[1], // lat
              e[0], // lon
            ),
          )
          .toList();

      if (coords.length < 2) {
        throw Exception('경로 좌표가 2개 미만입니다.');
      }

      if (_routeOverlay != null) {
        _mapController!.deleteOverlay(
          NOverlayInfo(
            type: NOverlayType.pathOverlay,
            id: _routeOverlay!.info.id,
          ),
        );
      }

      final route = NPathOverlay(
        id: 'route_to_${facility.id}',
        coords: coords,
      );
      _routeOverlay = route;

      _mapController!.addOverlay(route);

      final mid = coords[coords.length ~/ 2];
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: mid, zoom: 14),
      );

      log('[MAP] 경로 오버레이 추가, 포인트 수=${coords.length}');
    } catch (e, st) {
      log('[MAP] 경로 그리기 실패: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('경로 그리기 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }
}
