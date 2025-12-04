import 'package:flutter/material.dart';

class SitAndReachTestPage extends StatefulWidget {
  const SitAndReachTestPage({super.key});

  @override
  State<SitAndReachTestPage> createState() => _SitAndReachTestPageState();
}

class _SitAndReachTestPageState extends State<SitAndReachTestPage> {
  final TextEditingController _recordController = TextEditingController();

  @override
  void dispose() {
    _recordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("앉아서 허리 굽히기"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 안내 이미지/아이콘
            const Icon(Icons.accessibility_new, size: 80, color: Colors.teal),
            const SizedBox(height: 30),

            // 2. 안내 문구
            const Text(
              "무릎을 펴고 앉아 상체를 굽힌 후\n손끝이 닿은 거리를 측정해주세요.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 50),

            // 3. 기록 입력창
            const Text(
              "측정 결과 (cm)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _recordController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ), // 소수점 입력 가능
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "0.0",
                suffixText: "cm",
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

            // 4. 저장 버튼
            ElevatedButton(
              onPressed: () {
                if (_recordController.text.isEmpty) return;

                // 입력값(실수)을 가지고 이전 화면으로 돌아감
                double? result = double.tryParse(_recordController.text);
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
      ),
    );
  }
}
