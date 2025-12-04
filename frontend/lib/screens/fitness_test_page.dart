import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/physical_age_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FitnessTestPage extends StatefulWidget {
  const FitnessTestPage({super.key});

  @override
  State<FitnessTestPage> createState() => _FitnessTestPageState();
}

class _FitnessTestPageState extends State<FitnessTestPage> {
  double? _sitUpRecord;
  double? _flexibilityRecord;
  double? _jumpRecord;
  double? _heartRateRecord;

  bool _loading = false;
  String? _gradeLabel;
  double? _percentile;
  String? _weakPoint;
  List<PhysicalAgeHistoryRecord> _ageHistory = [];

  final _physicalAgeApi = PhysicalAgeApi();

  Future<void> _saveData() async {
    if (_sitUpRecord == null ||
        _flexibilityRecord == null ||
        _jumpRecord == null ||
        _heartRateRecord == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("모든 항목을 입력해주세요.")),
      );
      return;
    }

    setState(() => _loading = true);
    final user = Supabase.instance.client.auth.currentUser;

    try {
      final result = await _physicalAgeApi.predictPhysicalAge(
        userId: user?.id,
        sex: 'M', // TODO: 유저 정보에 따라 변경
        sitUps: _sitUpRecord!,
        flexibility: _flexibilityRecord!,
        jumpPower: _jumpRecord!,
        cardioEndurance: _heartRateRecord!,
      );

      setState(() {
        _gradeLabel = result.gradeLabel;
        _percentile = result.percentile;
        _weakPoint = result.weakPoint;
      });

      await _loadHistory();
    } catch (e) {
      print("측정 실패: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final rows = await _physicalAgeApi.fetchHistory(user.id);
    setState(() => _ageHistory = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("신체나이 측정")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_gradeLabel != null)
              Column(
                children: [
                  Text("나의 신체등급: $_gradeLabel",
                      style: const TextStyle(fontSize: 22)),
                  Text("백분위 점수: ${_percentile!.toStringAsFixed(1)}%",
                      style: const TextStyle(fontSize: 18)),
                  if (_weakPoint != null)
                    Text("취약영역: $_weakPoint",
                        style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 20),
                  _buildHistoryChart(),
                ],
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _saveData,
              child: const Text("측정하기"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryChart() {
    if (_ageHistory.isEmpty) {
      return const Text("아직 측정 기록이 없어요.");
    }

    List<FlSpot> spots = [];
    for (int i = 0; i < _ageHistory.length; i++) {
      final record = _ageHistory[i];
      final gradeIndex = record.gradeIndex;
      final gradeLabel = record.gradeLabel;
      final percentile = record.percentile;
      final weakPoint = record.weakPoint;
      // ...
    }


    double maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 5;
    double minY = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b) - 5;
    if (minY < 0) minY = 0;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: spots.length.toDouble() - 1,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.teal,
              barWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
