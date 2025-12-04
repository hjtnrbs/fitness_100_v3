import 'dart:async';
import 'package:flutter/material.dart';

// [변경] 클래스 이름: StandingJumpTestPage -> JumpPowerTestPage
class JumpPowerTestPage extends StatefulWidget {
  const JumpPowerTestPage({super.key});

  @override
  State<JumpPowerTestPage> createState() => _JumpPowerTestPageState();
}

class _JumpPowerTestPageState extends State<JumpPowerTestPage> {
  static const int _initialTime = 5; // 개발용 5초

  int _secondsRemaining = _initialTime;
  Timer? _timer;
  bool _isTimerRunning = false;
  bool _isTimerCompleted = false;

  // 카운트다운 관련
  bool _isCountdownActive = false;
  int _countdownValue = 3; // 3, 2, 1

  final TextEditingController _countController = TextEditingController();

  void _startCountdown() {
    setState(() {
      _isCountdownActive = true;
      _countdownValue = 3;
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdownValue > 1) {
          _countdownValue--;
        } else {
          timer.cancel();
          _isCountdownActive = false;
          _startMainTimer(); // 카운트다운 끝나면 실제 타이머 시작
        }
      });
    });
  }

  void _startMainTimer() {
    setState(() {
      _isTimerRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
        setState(() {
          _isTimerRunning = false;
          _isTimerCompleted = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("측정이 종료되었습니다! 횟수를 입력해주세요.")),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    int min = seconds ~/ 60;
    int sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("제자리 뛰기 (순발력)"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 메인 화면
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _formatTime(_secondsRemaining),
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: _isTimerRunning ? Colors.redAccent : Colors.teal,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                const Text(
                  "30초 동안 제자리 뛰기를 몇 회 했는지\n갯수를 세주세요.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 50),

                if (!_isTimerRunning && !_isTimerCompleted && !_isCountdownActive)
                  ElevatedButton(
                    onPressed: _startCountdown,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "측정 시작",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (_isTimerRunning)
                  Column(
                    children: [
                      const LinearProgressIndicator(color: Colors.teal),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () {
                          _timer?.cancel();
                          setState(() {
                            _isTimerRunning = false;
                            _secondsRemaining = _initialTime;
                          });
                        },
                        child: const Text("중단하고 리셋"),
                      ),
                    ],
                  )
                else if (_isTimerCompleted)
                  Column(
                    children: [
                      const Text(
                        "측정 결과 (회)",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _countController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: "0",
                          suffixText: "회",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          if (_countController.text.isEmpty) return;

                          int? result = int.tryParse(_countController.text);
                          if (result != null) {
                            Navigator.pop(context, result);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "기록 저장하기",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // 카운트다운 오버레이
          if (_isCountdownActive)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Text(
                  "$_countdownValue",
                  style: const TextStyle(
                    fontSize: 150,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
