import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_service.dart';
import '../main_navigator.dart';
import 'complete_profile_screen.dart';

// ==================== OTP ЕКРАН ====================
class OTPVerificationScreen extends StatefulWidget {
  final String phone;
  const OTPVerificationScreen({super.key, required this.phone});

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final _otpController = TextEditingController();
  bool _submitting = false;

  // Додано таймер на 120 секунд
  int _secondsRemaining = 120;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _otpController.addListener(_autoSubmitIfReady);
    _startTimer();
  }

  @override
  void dispose() {
    _otpController.removeListener(_autoSubmitIfReady);
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _secondsRemaining = 120);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  // Метод для повторної відправки коду
  Future<void> _resendOTP() async {
    setState(() => _submitting = true);
    try {
      await SupabaseService.client.auth.signInWithOtp(
        phone: widget.phone,
        channel: OtpChannel.sms,
      );
      _startTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код відправлено повторно! 📩'), backgroundColor: Colors.blue));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _autoSubmitIfReady() {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');
    if (code.length == 6 && !_submitting) {
      _verifyOTP();
    }
    // Оновлюємо UI для промальовки квадратиків
    setState(() {});
  }

  Future<void> _ensureProfileRow() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    await SupabaseService.client.from('profiles').upsert({
      'user_id': user.id,
      'phone': user.phone,
    });
  }

  Future<void> _postLoginRoute() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final profile = await SupabaseService.client
        .from('profiles')
        .select('full_name, address')
        .eq('user_id', user.id)
        .maybeSingle();

    final fullName = (profile?['full_name'] as String?)?.trim();
    final address = (profile?['address'] as String?)?.trim();

    final needsProfile = (fullName == null || fullName.isEmpty) || (address == null || address.isEmpty);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => needsProfile ? const CompleteProfileScreen() : const MainNavigator()),
          (route) => false,
    );
  }

  Future<void> _verifyOTP() async {
    if (_submitting) return;

    // Використовуємо setState, щоб показати лоадер
    setState(() => _submitting = true);

    try {
      final code = _otpController.text.replaceAll(RegExp(r'\D'), '');

      if (code.length != 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введіть 6 цифр коду')),
        );
        setState(() => _submitting = false);
        return;
      }

      final phone = widget.phone.trim();

      final response = await SupabaseService.client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.sms,
      );

      if (response.session != null) {
        await _ensureProfileRow();
        await _postLoginRoute();
        if (mounted) setState(() => _submitting = false);
        return;
      }

      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося підтвердити код')),
      );
    } on AuthException catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth: ${e.message}')),
      );
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    }
  }

  // КАСТОМНИЙ ВІДЖЕТ ДЛЯ ВВОДУ СМС
  Widget _buildOtpBoxes() {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final char = index < code.length ? code[index] : '';
              final isFocused = index == code.length;

              return Container(
                width: 45,
                height: 55,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFocused ? const Color(0xFFFFCD00) : Colors.white.withOpacity(0.5),
                      width: isFocused ? 2 : 1,
                    ),
                    boxShadow: [
                      if (isFocused) BoxShadow(color: const Color(0xFFFFCD00).withOpacity(0.3), blurRadius: 8, spreadRadius: 1)
                    ]
                ),
                child: Text(char, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
              );
            }),
          ),
          Positioned.fill(
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              showCursor: false,
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              // onChanged обробляється через _otpController.addListener в initState
            ),
          ),
        ],
      ),
    );
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
          color: Colors.black.withOpacity(0.6),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                          const Text('Підтвердження', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                          const SizedBox(height: 8),
                          Text('Введіть 6-значний код, який ми відправили на номер:\n${widget.phone}', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8), height: 1.4), textAlign: TextAlign.center),
                          const SizedBox(height: 32),

                          _buildOtpBoxes(),

                          const SizedBox(height: 32),

                          _submitting
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFCD00)))
                              : const SizedBox.shrink(),

                          const SizedBox(height: 16),

                          TextButton(
                            onPressed: _secondsRemaining == 0 && !_submitting ? _resendOTP : null,
                            child: Text(
                              _secondsRemaining > 0
                                  ? 'Відправити код повторно через ${_secondsRemaining}с'
                                  : 'Відправити код ще раз',
                              style: TextStyle(
                                color: _secondsRemaining > 0 ? Colors.white.withOpacity(0.5) : const Color(0xFFFFCD00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
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
}