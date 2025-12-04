import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart'; // [추가] 그래프 패키지
import 'package:intl/intl.dart'; // [추가] 날짜 포맷
import '../screens/fitness_test_page.dart';
import '../screens/profile_edit_page.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  String _nickname = "";
  String _physicalAgeText = "로딩 중...";

  double _sitUpScore = 0.1;
  double _flexScore = 0.1;
  double _jumpScore = 0.1;
  double _cardioScore = 0.1;

  // 배틀 전적
  int _winCount = 0;
  int _loseCount = 0;
  int _winRate = 0;

  // [추가] 신체나이 히스토리 데이터 (그래프용)
  List<Map<String, dynamic>> _ageHistory = [];
  bool _isHistoryLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyData();
  }

  Future<void> _loadMyData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _nickname = "로그인 필요";
          _physicalAgeText = "로그인 필요";
          _isHistoryLoading = false;
        });
      }
      return;
    }

    final nick = user.userMetadata?['nickname'] ?? "사용자";
    if (mounted) setState(() => _nickname = nick);

    try {
      // 1. 최신 신체나이 및 스탯 가져오기
      final latestData = await Supabase.instance.client
          .from('physical_age_assessments')
          .select()
          .eq('user_id', user.id)
          .order('measured_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // 2. [추가] 신체나이 변화 추이 가져오기 (전체 기록)
      final historyData = await Supabase.instance.client
          .from('physical_age_assessments')
          .select('measured_at')
          .eq('user_id', user.id)
          .order('measured_at', ascending: true); // 과거 -> 최신 순 정렬

      // 3. 배틀 전적 가져오기
      final battleResponse = await Supabase.instance.client
          .from('weekly_battles')
          .select('winner_user_id')
          .or('user_a_id.eq.${user.id},user_b_id.eq.${user.id}');

      // -- 배틀 승률 계산 로직 --
      int wins = 0;
      int others = 0;
      final List<dynamic> battles = battleResponse;
      for (var battle in battles) {
        final winnerId = battle['winner_user_id'];
        if (winnerId == user.id) {
          wins++;
        } else {
          others++;
        }
      }
      int totalBattles = wins + others;
      int calculatedWinRate = totalBattles > 0
          ? ((wins / totalBattles) * 100).round()
          : 0;

      // -- UI 업데이트 --
      String newAgeText = "측정 기록 없음";

      if (latestData != null) {
        final String? label = latestData['lo_age_tier_label'] as String?;
        final int? tierIndex = (latestData['tier_index'] as num?)?.toInt();

        String newAgeText = "측정 기록 없음";

        if (label != null) {
          newAgeText = label;              // 예: "40대 중반"
        } else if (tierIndex != null) {
          newAgeText = "신체나이 등급: ${tierIndex + 1} / 17";
}

        int sitUps = (latestData['sit_ups'] as num?)?.toInt() ?? 0;
        double flex = (latestData['flexibility'] as num?)?.toDouble() ?? 0.0;
        int jump = (latestData['jump_power'] as num?)?.toInt() ?? 0;
        int cardio = (latestData['cardio_endurance'] as num?)?.toInt() ?? 0;

        if (mounted) {
          setState(() {
            _physicalAgeText = newAgeText;
            _sitUpScore = (sitUps / 60.0).clamp(0.1, 1.0);
            _flexScore = ((flex + 10) / 40.0).clamp(0.1, 1.0);
            _jumpScore = (jump / 80.0).clamp(0.1, 1.0);
            _cardioScore = (1.0 - (cardio - 60) / 100.0).clamp(0.1, 1.0);

            _winCount = wins;
            _loseCount = others;
            _winRate = calculatedWinRate;

            // [추가] 히스토리 데이터 저장
            _ageHistory = List<Map<String, dynamic>>.from(historyData);
            _isHistoryLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _physicalAgeText = "아직 측정 기록이 없습니다.";
            _winCount = wins;
            _loseCount = others;
            _winRate = calculatedWinRate;
            _isHistoryLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("데이터 로딩 에러 발생: $e");
      if (mounted) {
        setState(() {
          _physicalAgeText = "기록 불러오기 실패";
          _isHistoryLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("로그아웃 실패")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 배틀 그래프 flex 계산
    int total = _winCount + _loseCount;
    int winFlex = total == 0 ? 1 : _winCount;
    int loseFlex = total == 0 ? 1 : _loseCount;
    bool hasNoBattle = total == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("마이페이지"),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () {},
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _loadMyData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              // 1. 프로필
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _nickname.isEmpty ? "..." : _nickname,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(
                      Icons.person,
                      size: 36,
                      color: Colors.lightBlue,
                    ),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileEditPage(),
                        ),
                      );
                      if (result == true) _loadMyData();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "신체나이: $_physicalAgeText",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),

              // 2. 마이 이지팟 버튼
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("마이 이지팟 히스토리 화면으로 이동")),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "마이 이지팟",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // 3. 미션 그래프
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "미션 그래프",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildBar("근지구력", _sitUpScore, Colors.lightBlueAccent),
                  _buildBar("유연성", _flexScore, Colors.lightBlueAccent),
                  _buildBar("순발력", _jumpScore, Colors.lightBlueAccent),
                  _buildBar("심폐지구력", _cardioScore, Colors.lightBlueAccent),
                ],
              ),
              const SizedBox(height: 40),

              // 4. 신체나이 동갑 배틀
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "신체나이 동갑 배틀",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: winFlex,
                            child: Container(
                              decoration: BoxDecoration(
                                color: hasNoBattle
                                    ? Colors.grey[300]
                                    : Colors.lightBlueAccent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "승 $_winCount",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: loseFlex,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "패 $_loseCount",
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "승률 $_winRate%",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // 5. [추가] 신체나이 변화 추이 그래프 (Line Chart)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "신체나이 변화 추이",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 15),
              _buildAgeHistoryChart(), // 그래프 위젯 호출
              const SizedBox(height: 40),

              // 6. 신체나이 재측정 버튼
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FitnessTestPage(),
                          ),
                        );
                        _loadMyData();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      child: const Text(
                        "신체나이 재측정",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "※ 1일 미션 30개 시 활성화",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // 7. 로그아웃
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, color: Colors.grey),
                label: const Text(
                  "로그아웃",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 막대 그래프 빌더
  Widget _buildBar(String label, double pct, Color color) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 100 * pct,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // [추가] 신체나이 라인 차트 위젯
  Widget _buildAgeHistoryChart() {
    if (_isHistoryLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_ageHistory.isEmpty) {
      return Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(child: Text("측정 기록이 없어 그래프를 표시할 수 없습니다.")),
      );
    }

    // 데이터 포인트 생성
    List<FlSpot> spots = [];
    for (int i = 0; i < _ageHistory.length; i++) {
      final item = _ageHistory[i];

      // tier_index가 없으면 16(최하위)로 처리
      final int tierIndex = (item['tier_index'] as num?)?.toInt() ?? 16;

      // 그래프 Y 값 = 16 - tierIndex (높은 등급 = 높은 점수)
      final double score = (16 - tierIndex).toDouble();

      spots.add(FlSpot(i.toDouble(), score));
    }

    // Y축 범위 설정 (0 ~ 16 그대로)
    double maxY = 16;
    double minY = 0;


    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (value) {
              return FlLine(color: Colors.grey.shade200, strokeWidth: 1);
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1, // X축 간격
                getTitlesWidget: (value, meta) {
                  int index = value.toInt();
                  if (index >= 0 && index < _ageHistory.length) {
                    // 날짜 표시 (예: 12/04)
                    final dateStr = _ageHistory[index]['measured_at'];
                    if (dateStr != null) {
                      final date = DateTime.parse(dateStr);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          DateFormat('MM/dd').format(date),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}세',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, // 곡선 처리
              color: Colors.teal,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: true), // 데이터 포인트 점 표시
              belowBarData: BarAreaData(
                show: true,
                color: Colors.teal.withOpacity(0.1), // 아래 영역 색칠
              ),
            ),
          ],
        ),
      ),
    );
  }
}
