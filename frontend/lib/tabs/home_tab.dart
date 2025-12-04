import 'package:flutter/material.dart';

class HomeTab extends StatelessWidget {
  // 탭 변경 요청을 보내기 위한 함수
  final Function(int)? onTabChange;

  const HomeTab({super.key, this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Low Age"),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 로고 이미지
              Image.asset(
                'assets/logo.png',
                width: 150,
                height: 150,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.bolt, size: 100, color: Colors.teal),
              ),
              const SizedBox(height: 60),

              // 1. 이지팟 버튼
              _buildMenuButton(
                title: "이지팟",
                onPressed: () {
                  // 탭 인덱스 1번(이지팟)으로 이동 요청
                  if (onTabChange != null) onTabChange!(1);
                },
              ),
              const SizedBox(height: 16),

              // 2. 마이페이지 버튼 (이름 변경됨)
              _buildMenuButton(
                title: "마이페이지",
                onPressed: () {
                  // 탭 인덱스 2번(마이페이지)으로 이동 요청
                  if (onTabChange != null) onTabChange!(2);
                },
              ),
              const SizedBox(height: 16),

              // 3. 신체나이 또래배틀 버튼 (이름 변경됨)
              _buildMenuButton(
                title: "신체나이 또래배틀",
                onPressed: () {
                  // 탭 인덱스 3번(또래배틀)으로 이동 요청
                  if (onTabChange != null) onTabChange!(3);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 메뉴 버튼 디자인 위젯
  Widget _buildMenuButton({
    required String title,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
        backgroundColor: const Color(0xFFF5F5F5), // 연한 회색 배경
        foregroundColor: Colors.black, // 검은색 글씨
        elevation: 0, // 그림자 없음
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4), // 약간 둥근 모서리
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
