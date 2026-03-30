<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_service.dart';
import 'otp_verification_screen.dart';

// ==================== ЕКРАН ВИБОРУ АВТОРИЗАЦІЇ (виклик SMS Hook) ====================
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController(text: '+380');
  bool _loading = false;

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim().replaceAll(' ', '');

    if (!RegExp(r'^\+380\d{9}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введіть номер у форматі +380XXXXXXXXX')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await SupabaseService.client.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.sms,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OTPVerificationScreen(phone: phone),
        ),
      );
    } catch (e) {
      print('Помилка: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося надіслати SMS')),
      );
    }

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.6), // Затемнення для читабельності
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ЛОГОТИП
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                      ),
                      child: const Icon(Icons.delivery_dining, size: 80, color: Colors.white),
                    ),
                    const SizedBox(height: 32),

                    // СКЛЯНА ПАНЕЛЬ
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
                      ),
                      child: Column(
                        children: [
                          const Text('Вітаємо!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 8),
                          Text('Увійдіть, щоб замовляти смачну їжу', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)), textAlign: TextAlign.center),
                          const SizedBox(height: 32),

                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: '+380 XX XXX XX XX',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.9),
                              prefixIcon: const Icon(Icons.phone, color: Color(0xFF005BBB)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFCD00),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                              onPressed: _loading ? null : _sendOTP,
                              child: _loading
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : const Text('Отримати код SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
=======
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_service.dart';
import 'otp_verification_screen.dart';

// ==================== ЕКРАН ВИБОРУ АВТОРИЗАЦІЇ (виклик SMS Hook) ====================
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController(text: '+380');
  bool _loading = false;

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim().replaceAll(' ', '');

    if (!RegExp(r'^\+380\d{9}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введіть номер у форматі +380XXXXXXXXX')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await SupabaseService.client.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.sms,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OTPVerificationScreen(phone: phone),
        ),
      );
    } catch (e) {
      debugPrint('Помилка: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося надіслати SMS')),
      );
    }

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.6), // Затемнення для читабельності
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ЛОГОТИП
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                      ),
                      child: const Icon(Icons.delivery_dining, size: 80, color: Colors.white),
                    ),
                    const SizedBox(height: 32),

                    // СКЛЯНА ПАНЕЛЬ
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
                      ),
                      child: Column(
                        children: [
                          const Text('Вітаємо!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 8),
                          Text('Увійдіть, щоб замовляти смачну їжу', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)), textAlign: TextAlign.center),
                          const SizedBox(height: 32),

                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: '+380 XX XXX XX XX',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.9),
                              prefixIcon: const Icon(Icons.phone, color: Color(0xFF005BBB)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFCD00),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                              onPressed: _loading ? null : _sendOTP,
                              child: _loading
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : const Text('Отримати код SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}