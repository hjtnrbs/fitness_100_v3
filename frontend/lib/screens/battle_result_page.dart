import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BattleResultPage extends StatefulWidget {
  // 이전 화면에서 넘겨받을 배틀 데이터 (id, user_a_id, scores 등 포함)
  final Map<String, dynamic> battleData;

  const BattleResultPage({super.key, required this.battleData});

  @override
  State<BattleResultPage> createState() => _BattleResultPageState();
}

class _BattleResultPageState extends State<BattleResultPage> {
  String _resultText = "결과 확인 중...";
  Color _resultColor = Colors.black;
  bool _isWinner = false;
  bool _isDraw = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _processBattleResult();
  }

  // 승패 계산 및 DB 저장 로직
  Future<void> _processBattleResult() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final battle = widget.battleData;
      final String battleId = battle['id'];

      // 1. 점수 비교
      final int scoreA = (battle['user_a_missions'] as int?) ?? 0;
      final int scoreB = (battle['user_b_missions'] as int?) ?? 0;
      final String userA = battle['user_a_id'];
      final String userB = battle['user_b_id'];

      String? winnerId;

      if (scoreA > scoreB) {
        winnerId = userA;
      } else if (scoreB > scoreA) {
        winnerId = userB;
      } else {
        winnerId = null; // 무승부
      }

      // 2. DB에 승자 정보 업데이트 (이미 처리된 경우 생략 가능하지만, 확실히 하기 위해 업데이트)
      // * 주의: RLS 정책에 따라 update 권한이 있어야 합니다.
      if (winnerId != null) {
        await Supabase.instance.client
            .from('weekly_battles')
            .update({'winner_user_id': winnerId})
            .eq('id', battleId);
      }

      // 3. UI 상태 결정
      if (mounted) {
        setState(() {
          if (winnerId == null) {
            _resultText = "Draw"; // 무승부
            _resultColor = Colors.grey;
            _isDraw = true;
          } else if (winnerId == user.id) {
            _resultText = "You Win!";
            _resultColor = Colors.black;
            _isWinner = true;
          } else {
            _resultText = "You Lose :(";
            _resultColor = Colors.redAccent;
            _isWinner = false;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("결과 처리 중 오류: $e");
      if (mounted) {
        setState(() {
          _resultText = "오류 발생";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 연한 회색 배경
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 타이틀 바 (이미지와 유사하게 커스텀)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: const Color(0xFFE0E0E0), // 조금 더 진한 회색 헤더
              child: const Center(
                child: Text(
                  "신체나이 또래 배틀",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            // 2. 결과 텍스트 (중앙 배치)
            Expanded(
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _resultText,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900, // 두꺼운 폰트
                              color: _resultColor,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // 점수도 보여주면 좋음 (선택사항)
                          if (!_isLoading)
                            Text(
                              "Score  ${widget.battleData['user_a_missions'] ?? 0} : ${widget.battleData['user_b_missions'] ?? 0}",
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
              ),
            ),

            // 3. 확인 버튼 (하단 배치)
            Padding(
              padding: const EdgeInsets.only(bottom: 50, left: 40, right: 40),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    // 확인 누르면 뒤로가기
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlueAccent, // 하늘색 버튼
                    foregroundColor: Colors.black, // 글자색 검정
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0), // 각진 버튼 (이미지 참고)
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "확인",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
