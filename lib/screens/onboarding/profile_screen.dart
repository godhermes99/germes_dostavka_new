import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_service.dart';
import 'auth_gate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController(); // Тут тепер буде тільки вулиця і будинок

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;

  String? _phone;
  String? _error;

  // --- ДОДАНО: Змінні для вибору населеного пункту ---
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
    _loadProfile();
  }

  Future<void> _ensureProfileRow() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    await SupabaseService.client.from('profiles').upsert({
      'user_id': user.id,
      'phone': user.phone,
    });
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = "No user";
          _loading = false;
        });
        return;
      }

      _phone = user.phone;

      // ДОДАНО: зчитуємо колонку city з бази
      final data = await SupabaseService.client
          .from('profiles')
          .select('phone, full_name, city, address')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null) {
        await _ensureProfileRow();
      }

      final data2 = data ??
          await SupabaseService.client
              .from('profiles')
              .select('phone, full_name, city, address')
              .eq('user_id', user.id)
              .maybeSingle();

      _name.text = (data2?['full_name'] as String?)?.trim() ?? '';
      _address.text = (data2?['address'] as String?)?.trim() ?? '';

      // ДОДАНО: встановлюємо місто, якщо воно є в базі і співпадає з нашим списком
      final fetchedCity = (data2?['city'] as String?)?.trim();
      if (fetchedCity != null && _settlements.contains(fetchedCity)) {
        _selectedCity = fetchedCity;
      }

      setState(() {
        _loading = false;
        _editing = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'DB: ${e.message}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final fullName = _name.text.trim();
    final address = _address.text.trim(); // Це тепер вулиця

    // ДОДАНО: перевірка на вибір міста
    if (fullName.isEmpty || address.isEmpty || _selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заповніть імʼя, оберіть місто та вкажіть вулицю з будинком')),
      );
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      // ДОДАНО: зберігаємо city
      await SupabaseService.client.from('profiles').upsert({
        'user_id': user.id,
        'phone': user.phone,
        'full_name': fullName,
        'city': _selectedCity,
        'address': address,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профіль успішно збережено ✅')),
      );

      setState(() => _editing = false);
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('DB: ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    await SupabaseService.client.auth.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Widget _viewRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мій Профіль'),
        backgroundColor: const Color(0xFF005BBB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      )
          : SingleChildScrollView( // ДОДАНО: щоб клавіатура не перекривала контент
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (phone.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Телефон: $phone', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 24),

            if (!_editing) ...[
              _viewRow('Імʼя та Прізвище', _name.text.trim()),
              const SizedBox(height: 12),
              // Показуємо місто разом з вулицею
              _viewRow('Адреса доставки', '${_selectedCity ?? 'Місто не обрано'}\n${_address.text.trim()}'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit),
                  label: const Text('Змінити дані', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005BBB),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Вийти з акаунта', style: TextStyle(fontSize: 16)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Імʼя та Прізвище',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),

              // --- ДОДАНО: Випадаючий список міст ---
              DropdownButtonFormField<String>(
                value: _selectedCity,
                decoration: const InputDecoration(
                  labelText: 'Населений пункт',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
                items: _settlements.map((city) {
                  return DropdownMenuItem(
                    value: city,
                    child: Text(city),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCity = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Вулиця, будинок, квартира',
                  hintText: 'Наприклад: вул. Миру 15, кв. 4',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.home),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Зберегти', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _editing = false),
                  child: const Text('Скасувати', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}