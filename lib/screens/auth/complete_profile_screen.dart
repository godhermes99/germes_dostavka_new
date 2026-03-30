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

  // --- ДОДАНО: Змінні для вибору міста ---
  String? _selectedCity;
  final List<String> _settlements = [
    'м. Могилів-Подільський',
    'с. Немія',
    'с. Бронниця',
    'с. Серебрія',
    'с. Юрківці',
    'с. Озаринці'
  ];
  // ---------------------------------------

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
    // ДОДАНО: Додали city до запиту
        .select('full_name, address, city')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return;

    setState(() {
      _name.text = (profile?['full_name'] as String?) ?? '';
      _address.text = (profile?['address'] as String?) ?? '';

      // ДОДАНО: Підтягуємо місто, якщо воно раптом вже було збережене
      final fetchedCity = (profile?['city'] as String?)?.trim();
      if (fetchedCity != null && _settlements.contains(fetchedCity)) {
        _selectedCity = fetchedCity;
      }
    });
  }

  Future<void> _save() async {
    final fullName = _name.text.trim();
    final address = _address.text.trim();

    // ДОДАНО: Перевірка на те, чи обране місто
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
        'city': _selectedCity, // ДОДАНО: Зберігаємо місто в базу
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
      appBar: AppBar(
        title: const Text('Заповніть профіль', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF005BBB),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView( // ДОДАНО: Щоб клавіатура не перекривала поля
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (phone.isNotEmpty) ...[
              const Icon(Icons.phone_android, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              Text(phone, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 24),
            ],

            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Імʼя та Прізвище*',
                prefixIcon: const Icon(Icons.person, color: Color(0xFF005BBB)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // --- ДОДАНО: Випадаючий список міст ---
            DropdownButtonFormField<String>(
              value: _selectedCity,
              decoration: InputDecoration(
                labelText: 'Населений пункт*',
                hintText: 'Оберіть місто чи село',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.location_city, color: Color(0xFF005BBB)),
              ),
              items: _settlements.map((city) {
                return DropdownMenuItem(value: city, child: Text(city, style: const TextStyle(fontWeight: FontWeight.w500)));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCity = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // ----------------------------------------

            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: 'Вулиця, будинок, квартира*',
                hintText: 'Наприклад: вул. Миру 15, кв. 4',
                prefixIcon: const Icon(Icons.home, color: Color(0xFF005BBB)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    backgroundColor: const Color(0xFFFFCD00), // Жовта кнопка, як скрізь
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('Зберегти та увійти', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}