// lib/screens/mission_route_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility.dart';
import '../config/api_config.dart'; // apiUri('/mission/complete') 사용

class MissionRoutePage extends StatefulWidget {
  final Facility facility;
  final double startLat;
  final double startLon;

  // 목록 화면에서 넘겨주는 즐겨찾기 여부
  final bool isFavorite;

  const MissionRoutePage({
    super.key,
    required this.facility,
    required this.startLat,
    required this.startLon,
    required this.isFavorite,
  });

  @override
  State<MissionRoutePage> createState() => _MissionRoutePageState();
}

class _MissionRoutePageState extends State<MissionRoutePage> {
  NaverMapController? _mapController;
  bool _mapReady = false;

  /// not_started → started → arrived → completed
  String _step = 'not_started';
  bool _saving = false;

  // ---- 1) 미션 상태 로그 API 호출 ----
  Future<void> _logMission(String status) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 정보가 없습니다. 다시 로그인해 주세요.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final uri = apiUri('/mission/complete');

      final body = jsonEncode({
        'user_id': user.id,
        'facility_id': widget.facility.id,
        // 'mission_id': ...  // 추후 미션 테이블 연동 시 추가
        'status': status,            // "started" / "arrived" / "completed"
        'is_favorite': widget.isFavorite,  // ⭐ 목록에서 넘겨준 즐겨찾기 여부
      });

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (resp.statusCode != 200) {
        throw Exception('status=${resp.statusCode}, body=${resp.body}');
      }

      setState(() {
        if (status == 'started') {
          _step = 'started';
        } else if (status == 'arrived') {
          _step = 'arrived';
        } else if (status == 'completed') {
          _step = 'completed';
        }
      });

      String msg = '미션 상태가 저장되었습니다.';
      if (status == 'started') msg = '미션을 시작했어요!';
      if (status == 'arrived') msg = '이지팟에 도착했어요!';
      if (status == 'completed') msg = '미션을 완료했어요!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미션 상태 저장 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // ---- 2) 메인 버튼 라벨 & 동작 ----
  String get _mainButtonLabel {
    switch (_step) {
      case 'not_started':
        return '미션 시작';
      case 'started':
        return '이지팟 도착';
      case 'arrived':
        return '미션 완료';
      case 'completed':
        return '미션 완료됨';
      default:
        return '미션 시작';
    }
  }

  Future<void> _onMainButtonPressed() async {
    if (_step == 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 완료된 미션입니다.')),
      );
      return;
    }

    if (_step == 'not_started') {
      await _logMission('started');
    } else if (_step == 'started') {
      await _logMission('arrived');
    } else if (_step == 'arrived') {
      await _logMission('completed');
    }
  }

  // ---- 3) 스텝 칩 색상 ----
  Color _chipBg(String step) {
    if (_step == 'completed') {
      return Colors.teal;
    }
    if (step == 'started' && (_step == 'started' || _step == 'arrived')) {
      return Colors.teal;
    }
    if (step == 'arrived' && _step == 'arrived') {
      return Colors.teal;
    }
    if (step == 'completed' && _step == 'completed') {
      return Colors.teal;
    }
    return Colors.grey.shade300;
  }

  Color _chipText(String step) {
    final bg = _chipBg(step);
    return bg == Colors.teal ? Colors.white : Colors.black87;
  }

  Widget _stepChip(String step, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Chip(
          label: Center(child: Text(label)),
          backgroundColor: _chipBg(step),
          labelStyle: TextStyle(
            color: _chipText(step),
            fontSize: 13,
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  // ---- 4) UI ----
  @override
  Widget build(BuildContext context) {
    final f = widget.facility;

    return Scaffold(
      appBar: AppBar(
        title: const Text('미션팟 안내'),
      ),
      body: Column(
        children: [
          // 상단 지도 (경로 없이 시설 마커만)
          SizedBox(
            height: 260,
            child: NaverMap(
              options: NaverMapViewOptions(
                initialCameraPosition: NCameraPosition(
                  target: NLatLng(f.lat, f.lon),
                  zoom: 16,
                ),
                locationButtonEnable: false,
              ),
              onMapReady: (controller) async {
                _mapController = controller;
                _mapReady = true;

                final marker = NMarker(
                  id: 'mission_facility_${f.id}',
                  position: NLatLng(f.lat, f.lon),
                  caption: NOverlayCaption(text: f.name),
                );
                await controller.addOverlay(marker);
              },
            ),
          ),

          // 하단 내용
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.mission,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#${f.category}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '오늘 미션 진행 상태',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _stepChip('started', '시작'),
                      _stepChip('arrived', '도착'),
                      _stepChip('completed', '완료'),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _onMainButtonPressed,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _mainButtonLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
