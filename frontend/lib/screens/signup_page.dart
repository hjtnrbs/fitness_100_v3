import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fitness_test_page.dart'; // [추가] 체력측정 페이지 이동을 위해 임포트

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // 입력값 컨트롤러
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false; // 로딩 상태

  // 회원가입 처리 함수
  Future<void> _signUp() async {
    // 1. 비밀번호 확인
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      // 2. Supabase에 회원가입 요청
      await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'nickname': _nicknameController.text.trim(), // 추가 정보(닉네임) 저장
        },
      );

      if (mounted) {
        // [수정] 성공 시 안내 메시지 & 분기 처리 (체력측정 vs 건너뛰기)
        showDialog(
          context: context,
          barrierDismissible: false, // 버튼을 눌러야만 닫히도록 설정
          builder: (context) {
            return AlertDialog(
              title: const Text('가입 성공'),
              content: const Text(
                '회원가입이 완료되었습니다.\n원활한 서비스를 받으려면 체력측정을 먼저 하셔야 합니다.',
              ),
              actions: [
                // 1. 건너뛰기 버튼 -> 로그인 화면으로 이동
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // 팝업 닫기
                    Navigator.pop(context); // 로그인 화면으로 돌아가기
                  },
                  child: const Text(
                    '건너뛰기',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                // 2. 체력측정 시작 버튼 -> 측정 페이지로 이동
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // 팝업 닫기
                    // 로그인 화면 대신 체력측정 페이지로 이동 (Replace로 스택 교체)
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FitnessTestPage(),
                      ),
                    );
                  },
                  child: const Text(
                    '체력측정 시작',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      }
    } on AuthException catch (error) {
      // Supabase 에러 처리 (이미 있는 이메일 등)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      // 기타 에러
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("회원가입")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 닉네임 입력
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: "닉네임 입력",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 이메일 입력
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "이메일 입력",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // 비밀번호 입력
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "비밀번호 입력",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),

            // 비밀번호 확인
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "비밀번호 확인",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 20),

            // 약관 동의 (UI만 구현)
            Row(
              children: [
                Checkbox(value: false, onChanged: (v) {}),
                const Text("약관 동의"),
              ],
            ),
            const SizedBox(height: 20),

            // 제출 버튼
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text("제출하기"),
            ),
          ],
        ),
      ),
    );
  }
}
