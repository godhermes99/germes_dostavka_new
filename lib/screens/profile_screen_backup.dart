<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_service.dart';
import 'auth/auth_gate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;

  String? _phone;
  String? _error;

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

      final data = await SupabaseService.client
          .from('profiles')
          .select('phone, full_name, address')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null) {
        await _ensureProfileRow();
      }

      final data2 = data ??
          await SupabaseService.client
              .from('profiles')
              .select('phone, full_name, address')
              .eq('user_id', user.id)
              .maybeSingle();

      _name.text = (data2?['full_name'] as String?)?.trim() ?? '';
      _address.text = (data2?['address'] as String?)?.trim() ?? '';

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
    final address = _address.text.trim();

    if (fullName.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заповніть імʼя та адресу')),
      );
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      await SupabaseService.client.from('profiles').upsert({
        'user_id': user.id,
        'phone': user.phone,
        'full_name': fullName,
        'address': address,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профіль збережено')),
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
        title: const Text('Профіль'),
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
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (phone.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Телефон: $phone', style: const TextStyle(fontSize: 16)),
              ),
            const SizedBox(height: 16),

            if (!_editing) ...[
              _viewRow('Імʼя та Прізвище', _name.text.trim()),
              const SizedBox(height: 12),
              _viewRow('Адреса доставки', _address.text.trim()),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Змінити профіль'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _logout,
                  child: const Text('Вийти', style: TextStyle(color: Colors.white)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Імʼя та Прізвище',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Адреса доставки',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Зберегти'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                    setState(() => _editing = false);
                  },
                  child: const Text('Скасувати'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
=======
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_service.dart';
import 'auth/auth_gate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;

  String? _phone;
  String? _error;

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

      final data = await SupabaseService.client
          .from('profiles')
          .select('phone, full_name, address')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null) {
        await _ensureProfileRow();
      }

      final data2 = data ??
          await SupabaseService.client
              .from('profiles')
              .select('phone, full_name, address')
              .eq('user_id', user.id)
              .maybeSingle();

      _name.text = (data2?['full_name'] as String?)?.trim() ?? '';
      _address.text = (data2?['address'] as String?)?.trim() ?? '';

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
    final address = _address.text.trim();

    if (fullName.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заповніть імʼя та адресу')),
      );
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      await SupabaseService.client.from('profiles').upsert({
        'user_id': user.id,
        'phone': user.phone,
        'full_name': fullName,
        'address': address,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профіль збережено')),
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
        title: const Text('Профіль'),
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
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (phone.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Телефон: $phone', style: const TextStyle(fontSize: 16)),
              ),
            const SizedBox(height: 16),

            if (!_editing) ...[
              _viewRow('Імʼя та Прізвище', _name.text.trim()),
              const SizedBox(height: 12),
              _viewRow('Адреса доставки', _address.text.trim()),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Змінити профіль'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _logout,
                  child: const Text('Вийти', style: TextStyle(color: Colors.white)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Імʼя та Прізвище',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Адреса доставки',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Зберегти'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                    setState(() => _editing = false);
                  },
                  child: const Text('Скасувати'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}