import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_gate.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _finish(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGate()));
  }

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(title: "Швидка доставка", body: "Смачна їжа за 30 хвилин", image: const Icon(Icons.delivery_dining, size: 180, color: Color(0xFF005BBB))),
        PageViewModel(title: "Великий вибір", body: "Піца • Суші • Борщ • Вареники", image: const Icon(Icons.restaurant_menu, size: 180, color: Color(0xFFFFCD00))),
        PageViewModel(title: "Зручно та надійно", body: "Відстежуй кур’єра в реальному часі", image: const Icon(Icons.map_outlined, size: 180, color: Color(0xFF005BBB))),
      ],
      onDone: () => _finish(context),
      onSkip: () => _finish(context),
      showSkipButton: true,
      skip: const Text("Пропустити"),
      next: const Icon(Icons.arrow_forward),
      done: const Text("Почати", style: TextStyle(fontWeight: FontWeight.bold)),
      dotsDecorator: const DotsDecorator(activeColor: Color(0xFF005BBB)),
    );
  }
}