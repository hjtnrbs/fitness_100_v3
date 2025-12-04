import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // [추가] DB 조회를 위해 추가
import '../tabs/home_tab.dart';
import '../tabs/map_mission_view.dart';
import '../tabs/my_page.dart';
import '../tabs/peer_battle_tab.dart';
import 'fitness_test_page.dart'; // [추가] 측정 페이지 이동을 위해 추가

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // 화면이 처음 그려진 직후에 기록 확인 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFitnessRecord();
    });
  }

  // [기능 추가] 체력 측정 기록이 있는지 확인하고 없으면 알림
  Future<void> _checkFitnessRecord() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 내 기록이 하나라도 있는지 확인 (limit 1로 효율 조회)
      final data = await Supabase.instance.client
          .from('physical_age_assessments')
          .select('id') // id만 가져와서 존재 여부 확인
          .eq('user_id', user.id)
          .limit(1)
          .maybeSingle();

      // 기록이 없다면 스낵바 띄우기
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("체력측정을 해야 원활한 서비스를 받으실 수 있습니다."),
              backgroundColor: Colors.orange, // 경고 느낌의 주황색
              duration: const Duration(seconds: 5), // 5초 동안 표시
              action: SnackBarAction(
                label: "측정하러 가기",
                textColor: Colors.white,
                onPressed: () {
                  // 측정 페이지로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FitnessTestPage(),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("체력 기록 확인 중 오류 발생: $e");
    }
  }

  // 탭을 변경하는 함수
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 탭 화면 리스트
    final List<Widget> pages = [
      // [중요] HomeTab에 탭 변경 함수(_onItemTapped)를 전달합니다.
      HomeTab(onTabChange: _onItemTapped),
      const MapMissionView(),
      const MyPage(),
      const PeerBattleTab(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped, // 하단 탭을 눌렀을 때 실행될 함수
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "홈"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "이지팟"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "마이페이지"),
          BottomNavigationBarItem(icon: Icon(Icons.sports_mma), label: "또래배틀"),
        ],
      ),
    );
  }
}
