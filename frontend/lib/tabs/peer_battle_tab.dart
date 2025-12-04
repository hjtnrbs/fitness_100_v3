import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/battle_result_page.dart'; // [추가] 결과 페이지 임포트

class PeerBattleTab extends StatefulWidget {
  const PeerBattleTab({super.key});

  @override
  State<PeerBattleTab> createState() => _PeerBattleTabState();
}

class _PeerBattleTabState extends State<PeerBattleTab> {
  // 내 정보
  String _myNickname = "나";
  int _myScore = 0; // 내 이번주 미션 성공 횟수
  String _myLoAgeLabel = ""; // 내 신체나이 등급

  // 상대 정보
  String _opponentNickname = "상대 찾는 중...";
  int _opponentScore = 0; // 상대 이번주 미션 성공 횟수
  bool _isOpponentFound = false;
  String _opponentLoAgeLabel = ""; // 상대 신체나이 등급
  String _statusMessage = "상대를 찾는 중입니다..."; // 상태 메시지

  bool _isLoading = true;

  // 신체나이 등급 리스트 (순서대로 정렬됨)
  final List<String> _tierList = [
    "10대",
    "20대 초반",
    "20대 중반",
    "20대 후반",
    "30대 초반",
    "30대 중반",
    "30대 후반",
    "40대 초반",
    "40대 중반",
    "40대 후반",
    "50대 초반",
    "50대 중반",
    "50대 후반",
    "60대 초반",
    "60대 중반",
    "60대 후반",
    "70대 이상",
  ];

  @override
  void initState() {
    super.initState();
    _initializeBattle();
  }

  // 이번 주의 시작일(월요일 00:00:00) 구하기
  DateTime _getStartOfWeek() {
    final now = DateTime.now();
    // 월요일=1, ... 일요일=7
    final diff = now.weekday - 1;
    final startOfWeek = DateTime(now.year, now.month, now.day - diff);
    return startOfWeek;
  }

  // 특정 유저의 이번 주 미션 성공 횟수 조회
  Future<int> _getWeeklyMissionCount(String userId) async {
    try {
      final startOfWeek = _getStartOfWeek();
      final countResponse = await Supabase.instance.client
          .from('mission_logs')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .gte('created_at', startOfWeek.toIso8601String());

      return countResponse;
    } catch (e) {
      debugPrint("미션 카운트 조회 실패 ($userId): $e");
      return 0;
    }
  }

  // 배틀 데이터 초기화 (조건부 매칭)
  Future<void> _initializeBattle() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      // 1. 내 정보 및 등급 가져오기
      final myNick = user.userMetadata?['nickname'] ?? "나";
      String myLabel = "측정불가";

      try {
        final myData = await supabase
            .from('physical_age_assessments')
            .select('lo_age_tier_label')
            .eq('user_id', user.id)
            .order('measured_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (myData != null) {
          myLabel = (myData['lo_age_tier_label'] as String?) ?? "측정불가";
        }
      } catch (e) {
        debugPrint("내 등급 조회 실패: $e");
      }

      // 내 점수 미리 계산
      final myMissionCount = await _getWeeklyMissionCount(user.id);

      setState(() {
        _myNickname = myNick;
        _myLoAgeLabel = myLabel;
        _myScore = myMissionCount;
      });

      // 2. 상대 찾기 로직 시작
      if (myLabel != "측정불가") {
        // (A) 1순위: 같은 등급 검색
        var opponentCandidates = await supabase
            .from('physical_age_assessments')
            .select('user_id, lo_age_tier_label')
            .neq('user_id', user.id) // 나 제외
            .eq('lo_age_tier_label', myLabel)
            .order('measured_at', ascending: false)
            .limit(50);

        // (B) 2순위: 없으면 앞뒤 등급(±1단계) 검색
        if ((opponentCandidates as List).isEmpty) {
          final tierIndex = _tierList.indexOf(myLabel);

          if (tierIndex != -1) {
            // 앞뒤 등급 찾기
            List<String> adjacentTiers = [];
            if (tierIndex > 0) adjacentTiers.add(_tierList[tierIndex - 1]);
            if (tierIndex < _tierList.length - 1) {
              adjacentTiers.add(_tierList[tierIndex + 1]);
            }

            if (adjacentTiers.isNotEmpty) {
              // OR 조건 문자열 생성 (예: lo_age_tier_label.eq.30대초반,lo_age_tier_label.eq.30대후반)
              final orCondition = adjacentTiers
                  .map((t) => 'lo_age_tier_label.eq.$t')
                  .join(',');

              opponentCandidates = await supabase
                  .from('physical_age_assessments')
                  .select('user_id, lo_age_tier_label')
                  .neq('user_id', user.id)
                  .or(orCondition) // 앞뒤 등급 중 하나
                  .order('measured_at', ascending: false)
                  .limit(50);

              if ((opponentCandidates as List).isNotEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("같은 등급이 없어 비슷한 연령대와 매칭합니다.")),
                  );
                }
              }
            }
          }
        }

        // (C) 결과 처리
        if ((opponentCandidates as List).isNotEmpty) {
          // 매칭 성공: 랜덤 선택
          final random = Random();
          final selectedOpponent =
              opponentCandidates[random.nextInt(opponentCandidates.length)];
          final String opId = selectedOpponent['user_id'];
          final String opLabel =
              selectedOpponent['lo_age_tier_label'] ?? "등급없음";

          // 상대 점수 조회
          final opMissionCount = await _getWeeklyMissionCount(opId);

          // 상대 닉네임 조회
          String opNick = "라이벌";
          try {
            final profileData = await supabase
                .from('profiles')
                .select('nickname')
                .eq('id', opId)
                .maybeSingle();
            if (profileData != null && profileData['nickname'] != null) {
              opNick = profileData['nickname'];
            } else {
              final randomNicknames = [
                "운동하는직장인",
                "건강지킴이",
                "새벽러너",
                "헬스보이",
                "산책왕",
              ];
              opNick = randomNicknames[random.nextInt(randomNicknames.length)];
            }
          } catch (e) {
            final randomNicknames = ["운동하는직장인", "건강지킴이", "새벽러너", "헬스보이", "산책왕"];
            opNick = randomNicknames[random.nextInt(randomNicknames.length)];
          }

          if (mounted) {
            setState(() {
              _opponentNickname = opNick;
              _opponentScore = opMissionCount;
              _opponentLoAgeLabel = opLabel;
              _isOpponentFound = true;
              _statusMessage = "매칭 성공!";
            });
          }
        } else {
          // 매칭 실패 (±1단계까지 뒤져도 없음)
          if (mounted) {
            setState(() {
              _opponentNickname = "이용자 없음";
              _opponentScore = 0;
              _isOpponentFound = false;
              _statusMessage = "또래 신체나이의 이용자가 없습니다."; // 요청하신 문구
            });
          }
        }
      } else {
        // 내 등급 자체가 없을 때
        if (mounted) {
          setState(() {
            _opponentNickname = "정보 없음";
            _statusMessage = "먼저 신체나이를 측정해주세요.";
            _isOpponentFound = false;
          });
        }
      }
    } catch (e) {
      debugPrint("배틀 초기화 에러: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 승률(점유율) 계산
    final double totalScore = (_myScore + _opponentScore).toDouble();
    final int winRate = totalScore == 0
        ? 50
        : ((_myScore / totalScore) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text("신체나이 또래 배틀"),
        centerTitle: true,
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
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: () {
              setState(() => _isLoading = true);
              _initializeBattle();
            },
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // 매칭 안내
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "🎯 신체나이 [$_myLoAgeLabel] 매치",
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),

                  // 1. VS 배틀 섹션
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 나 (You)
                      Column(
                        children: [
                          _buildProfileAvatar(Colors.blue),
                          const SizedBox(height: 8),
                          Text(
                            _myNickname,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _myLoAgeLabel,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      // VS 텍스트
                      Column(
                        children: [
                          const Text(
                            "VS",
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: Colors.redAccent,
                            ),
                          ),
                          // 매칭 성공 여부에 따른 문구 표시
                          if (_isOpponentFound)
                            const Text(
                              "Rival Found!",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),

                      // 상대 (Opponent)
                      Column(
                        children: [
                          _buildProfileAvatar(Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            _opponentNickname,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // 매칭 결과/상태 메시지 표시
                          if (_isOpponentFound)
                            Text(
                              _opponentLoAgeLabel,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            )
                          else
                            Text(
                              _statusMessage, // "또래 신체나이의 이용자가 없습니다."
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // 2. Info Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Weekly Mission Score",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "$_myScore",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const Text(
                              " : ",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "$_opponentScore",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 3. Score Large Text
                  const Text(
                    "주간 미션 성공 (회)",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // You
                      Column(
                        children: [
                          Text(
                            "$_myScore",
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Text(
                            "My Missions",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 40, color: Colors.grey[300]),
                      // Opponent
                      Column(
                        children: [
                          Text(
                            "$_opponentScore",
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const Text(
                            "Rival",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // 4. Win Rate
                  const Text(
                    "현재 승률 (점유율)",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "$winRate%",
                    style: const TextStyle(
                      fontSize: 50,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: winRate / 100,
                        minHeight: 15,
                        backgroundColor: Colors.red.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.blue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (totalScore == 0)
                    const Text(
                      "아직 양쪽 모두 미션 기록이 없습니다.",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),

                  const SizedBox(height: 30),

                  // [수정됨] 테스트용 더미 ID를 실제 UUID 형식으로 변경하여 에러 방지
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent, // 눈에 띄게 빨간색
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        // 테스트용 더미 데이터
                        final dummyBattleData = {
                          // [수정] 유효한 UUID 형식의 가짜 ID 사용
                          'id': '00000000-0000-0000-0000-000000000000',
                          'user_a_id':
                              Supabase.instance.client.auth.currentUser?.id ??
                              'me',
                          'user_b_id': 'opponent-id',
                          'user_a_missions': 5, // 내가 이기는 시나리오
                          'user_b_missions': 3,
                        };

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                BattleResultPage(battleData: dummyBattleData),
                          ),
                        );
                      },
                      child: const Text(
                        "🛠️ [개발용] 결과 페이지 미리보기",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileAvatar(MaterialColor color) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(Icons.person, size: 50, color: color),
    );
  }
}
