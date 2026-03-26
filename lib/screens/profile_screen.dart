import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import '../core/supabase_service.dart';
import '../providers/theme_provider.dart';
import 'auth/auth_gate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _addressController = TextEditingController();
  String _name = '';
  String _phone = '';
  bool _isLoading = true;
  bool _isSaving = false;

  String? _selectedCity;
  final List<String> _settlements = [
    'м. Могилів-Подільський',
    'с. Немія',
    'с. Бронниця',
    'с. Серебрія',
    'с. Юрківці',
    'с. Озаринці'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      _phone = user.phone ?? 'Не вказано';

      final profile = await SupabaseService.client
          .from('profiles')
          .select('full_name, address, city')
          .eq('user_id', user.id)
          .single();

      setState(() {
        _name = profile['full_name'] ?? 'Без імені';
        _addressController.text = profile['address'] ?? '';

        final fetchedCity = profile['city']?.toString().trim();
        if (fetchedCity != null && _settlements.contains(fetchedCity)) {
          _selectedCity = fetchedCity;
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Помилка: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAddress() async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Будь ласка, оберіть місто зі списку! 🏘️'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        await SupabaseService.client
            .from('profiles')
            .update({
          'address': _addressController.text.trim(),
          'city': _selectedCity,
        })
            .eq('user_id', user.id);

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Адресу успішно оновлено! 🎉'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
      debugPrint('Firebase токен успішно видалено (Профіль Клієнта)');
    } catch (e) {
      debugPrint('Помилка видалення токена Firebase: $e');
    }

    await SupabaseService.client.auth.signOut();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
              (route) => false
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // 🔥 ВИЗНАЧАЄМО ТЕМУ
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔥 ДИНАМІЧНІ КОЛЬОРИ ДЛЯ КАРТОК
    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final hintColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Мій профіль', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 28),
            tooltip: 'Вийти з акаунту',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: ListView(
            // 🔥 Залишили відступ знизу 180, щоб селект міста відкривався без перекриття баром
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 20,
                left: 20,
                right: 20,
                bottom: 180
            ),
            children: [
              // === ІМ'Я ===
              const Text('Ім\'я (не можна змінити)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Text(_name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              ),
              const SizedBox(height: 20),

              // === ТЕЛЕФОН ===
              const Text('Телефон', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Text(_phone, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              ),
              const SizedBox(height: 30),

              // === ОФОРМЛЕННЯ (ТЕМА) ===
              const Text('Оформлення', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_suggest),
                          label: Text('Авто'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Світла'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Темна'),
                        ),
                      ],
                      selected: {themeProvider.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        themeProvider.setThemeMode(newSelection.first);
                      },
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),

              // === АДРЕСА ===
              const Text('Моя стандартна адреса доставки', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              const SizedBox(height: 10),

              // Місто
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: DropdownButtonFormField<String>(
                  value: _selectedCity,
                  dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Населений пункт',
                    labelStyle: TextStyle(color: hintColor),
                    prefixIcon: const Icon(Icons.location_city, color: Color(0xFF005BBB)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  items: _settlements.map((city) {
                    return DropdownMenuItem(value: city, child: Text(city));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedCity = value),
                ),
              ),
              const SizedBox(height: 16),

              // Вулиця
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: TextField(
                  controller: _addressController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Вулиця, будинок, квартира',
                    hintStyle: TextStyle(color: hintColor),
                    prefixIcon: const Icon(Icons.home, color: Color(0xFF005BBB)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // === КНОПКА ЗБЕРЕЖЕННЯ ===
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCD00),
                      elevation: 4,
                      shadowColor: Colors.black45,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  ),
                  onPressed: _isSaving ? null : _saveAddress,
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Зберегти адресу', style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}