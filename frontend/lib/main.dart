import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 1. 패키지 임포트

import 'screens/splash_screen.dart';
import 'screens/login_page.dart';
import 'screens/signup_page.dart';
import 'screens/home_page.dart';
import 'screens/map_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 환경변수 파일 로드
  // 파일이 없거나 읽지 못하면 에러가 날 수 있으므로 예외처리를 해주면 더 좋습니다.
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("ERROR: .env 파일을 찾을 수 없습니다. 프로젝트 루트에 .env 파일을 생성했는지, pubspec.yaml에 등록했는지 확인하세요.");
  }

  // 3. Supabase 초기화 (환경변수 값 사용)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '', // 값이 없으면 빈 문자열(에러 방지)
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    debug: true,
  );

  // 4. 네이버 지도 초기화 (환경변수 값 사용)
  await FlutterNaverMap().init(
    clientId: dotenv.env['NAVER_CLIENT_ID'] ?? '',
    onAuthFailed: (ex) => debugPrint('네이버맵 인증 실패: $ex'),
  );

  runApp(const LowAgeApp());
}

class LowAgeApp extends StatelessWidget {
  const LowAgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Low Age',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        fontFamily: 'NotoSansKR', // pubspec.yaml에 폰트 등록 확인 필요
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const HomePage(),
        '/map': (context) => const MapScreen(),   // ⭐ 이것만 추가!
      },
    );
  }
}