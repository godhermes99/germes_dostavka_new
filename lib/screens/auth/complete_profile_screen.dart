import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_service.dart';
import '../main_navigator.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _loading = false;

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
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final profile = await SupabaseService.client
        .from('profiles')
        .select('full_name, address, city')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return;

    setState(() {
      _name.text = (profile?['full_name'] as String?) ?? '';
      _address.text = (profile?['address'] as String?) ?? '';

      final fetchedCity = (profile?['city'] as String?)?.trim();
      if (fetchedCity != null && _settlements.contains(fetchedCity)) {
        _selectedCity = fetchedCity;
      }
    });
  }

  Future<void> _save() async {
    final fullName = _name.text.trim();
    final address = _address.text.trim();

    if (fullName.isEmpty || address.isEmpty || _selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Будь ласка, заповніть усі поля та оберіть місто 🏘️')),
      );
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      await SupabaseService.client.from('profiles').upsert({
        'user_id': user.id,
        'phone': user.phone,
        'full_name': fullName,
        'address': address,
        'city': _selectedCity,
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigator()),
            (_) => false,
      );
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DB: ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = SupabaseService.client.auth.currentUser?.phone ?? '';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Заповніть профіль',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                              ),
                            ),
                            if (phone.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.phone_android, size: 18, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Text(phone, style: const TextStyle(fontSize: 16, color: Colors.white70)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),

                            // Ім'я
                            TextField(
                              controller: _name,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Імʼя та Прізвище*',
                                labelStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.person, color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFFFCD00)),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.08),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),

                            // Місто
                            DropdownButtonFormField<String>(
                              value: _selectedCity,
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Населений пункт*',
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintText: 'Оберіть місто чи село',
                                hintStyle: const TextStyle(color: Colors.white38),
                                prefixIcon: const Icon(Icons.location_city, color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFFFCD00)),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.08),
                              ),
                              items: _settlements.map((city) {
                                return DropdownMenuItem(
                                  value: city,
                                  child: Text(city, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                );
                              }).toList(),
                              onChanged: (value) => setState(() => _selectedCity = value),
                            ),
                            const SizedBox(height: 16),

                            // Адреса
                            TextField(
                              controller: _address,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Вулиця, будинок, квартира*',
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintText: 'Наприклад: вул. Миру 15, кв. 4',
                                hintStyle: const TextStyle(color: Colors.white38),
                                prefixIcon: const Icon(Icons.home, color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFFFCD00)),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.08),
                              ),
                              minLines: 1,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 30),

                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFCD00),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _loading
                                    ? const CircularProgressIndicator(color: Colors.black)
                                    : const Text('Зберегти та увійти', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
