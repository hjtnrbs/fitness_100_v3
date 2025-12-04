import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 입력값을 가져오기 위한 컨트롤러
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false; // 로딩 상태 확인용

  // 로그인 처리 함수
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      // Supabase에 로그인 요청
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        // 로그인 성공 시 홈으로 이동
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (error) {
      // 로그인 실패 (아이디/비번 틀림 등)
      if (mounted) {
        // 에러 메시지에 [Supabase] 태그를 붙여 출처를 명확히 합니다.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('[Supabase 오류] ${error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      // 기타 에러
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('예기치 못한 오류가 발생했습니다: $error'),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("로그인")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController, // 컨트롤러 연결
              decoration: const InputDecoration(
                labelText: "이메일 입력",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController, // 컨트롤러 연결
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "비밀번호 입력",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: false, // (기능 미구현, UI만 유지)
                  onChanged: (val) {},
                ),
                const Text("자동 로그인 동의"),
                const Spacer(),
                TextButton(onPressed: () {}, child: const Text("계정 찾기")),
              ],
            ),
            const SizedBox(height: 20),

            // 로그인 버튼
            ElevatedButton(
              onPressed: _isLoading ? null : _signIn, // 로딩 중이면 클릭 방지
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
                  : const Text("시작하기", style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/signup');
              },
              child: const Text("회원가입"),
            ),
          ],
        ),
      ),
    );
  }
}
