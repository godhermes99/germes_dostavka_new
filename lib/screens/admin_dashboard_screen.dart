import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/supabase_service.dart';
import 'auth/auth_gate.dart';

// ============================================================================
// ПАНЕЛЬ ВЛАСНИКА (СУПЕР-АДМІНА) - ГОЛОВНИЙ КАРКАС
// ============================================================================
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  final List<String> _titles = [
    'Глобальна статистика',
    'Управління ресторанами',
    'Моніторинг кур\'єрів',
    'База клієнтів'
  ];

  Widget _buildFloatingNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final Color backgroundColor = isSelected ? const Color(0xFF005BBB) : Colors.white.withOpacity(0.95);
    final Color contentColor = isSelected ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(30),
          border: isSelected ? null : Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.2 : 0.05),
              blurRadius: isSelected ? 10 : 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: contentColor, size: 22),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: Text(label, style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        title: Text(_titles[_currentIndex], style: const TextStyle(fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Вийти з акаунту',
            onPressed: () async {
              await SupabaseService.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.white.withOpacity(0.05),
          child: IndexedStack(
            index: _currentIndex,
            children: [
              const AdminStatisticsTab(),
              const AdminRestaurantsTab(),
              const AdminCouriersTab(),
              const AdminClientsTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.only(bottom: 24, left: 12, right: 12),
        child: BottomAppBar(
          elevation: 0,
          color: Colors.transparent,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildFloatingNavItem(index: 0, icon: Icons.insert_chart, label: 'Стат', isSelected: _currentIndex == 0, onTap: () => setState(() => _currentIndex = 0)),
              _buildFloatingNavItem(index: 1, icon: Icons.storefront, label: 'Заклади', isSelected: _currentIndex == 1, onTap: () => setState(() => _currentIndex = 1)),
              _buildFloatingNavItem(index: 2, icon: Icons.moped, label: 'Кур\'єри', isSelected: _currentIndex == 2, onTap: () => setState(() => _currentIndex = 2)),
              _buildFloatingNavItem(index: 3, icon: Icons.people, label: 'Клієнти', isSelected: _currentIndex == 3, onTap: () => setState(() => _currentIndex = 3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ВКЛАДКА 1: ГЛОБАЛЬНА СТАТИСТИКА ТА НАЛАШТУВАННЯ (ДАШБОРД)
// ============================================================================
class AdminStatisticsTab extends StatefulWidget {
  const AdminStatisticsTab({super.key});

  @override
  State<AdminStatisticsTab> createState() => _AdminStatisticsTabState();
}

class _AdminStatisticsTabState extends State<AdminStatisticsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTimeRange? _selectedDateRange;
  int _selectedDays = 1;
  int _restaurantCount = 0;

  double _basePrice = 0.0;
  double _pricePerKm = 0.0;
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _setQuickFilter(1);
    _fetchRestaurantCount();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    try {
      final res = await SupabaseService.client.from('settings').select().eq('id', 1).maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _basePrice = (res['base_price'] as num?)?.toDouble() ?? 0.0;
          _pricePerKm = (res['price_per_km'] as num?)?.toDouble() ?? 0.0;
          _isLoadingSettings = false;
        });
      } else {
        await SupabaseService.client.from('settings').insert({'id': 1, 'base_price': 40, 'price_per_km': 10});
        if (mounted) {
          setState(() {
            _basePrice = 40.0;
            _pricePerKm = 10.0;
            _isLoadingSettings = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Помилка завантаження налаштувань: $e');
      if (mounted) setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _showEditSettingsDialog() async {
    final baseController = TextEditingController(text: _basePrice.toStringAsFixed(0));
    final kmController = TextEditingController(text: _pricePerKm.toStringAsFixed(0));
    bool isSaving = false;

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(
                    children: [
                      Icon(Icons.delivery_dining, color: Color(0xFF005BBB)),
                      SizedBox(width: 8),
                      Text('Тарифи доставки', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: baseController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Базова вартість (подача)',
                          suffixText: '₴',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: kmController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Вартість за 1 км',
                          suffixText: '₴/км',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Скасувати', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005BBB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: isSaving ? null : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final newBase = double.tryParse(baseController.text) ?? _basePrice;
                          final newKm = double.tryParse(kmController.text) ?? _pricePerKm;

                          await SupabaseService.client.from('settings').update({
                            'base_price': newBase,
                            'price_per_km': newKm,
                          }).eq('id', 1);

                          setState(() {
                            _basePrice = newBase;
                            _pricePerKm = newKm;
                          });

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Тарифи успішно оновлено! 🚀'), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                          setDialogState(() => isSaving = false);
                        }
                      },
                      child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Зберегти'),
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  Future<void> _fetchRestaurantCount() async {
    try {
      final res = await SupabaseService.client.from('restaurants').select('id');
      if (mounted) setState(() => _restaurantCount = res.length);
    } catch (e) {
      debugPrint('Помилка: $e');
    }
  }

  void _setQuickFilter(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDays = days;
      if (days == 1) {
        _selectedDateRange = DateTimeRange(start: today, end: today);
      } else {
        _selectedDateRange = DateTimeRange(
          start: today.subtract(Duration(days: days - 1)),
          end: today,
        );
      }
    });
  }

  Future<void> _pickDateRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: now,
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF005BBB))),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDays = 0;
        _selectedDateRange = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client.from('orders').stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final allOrders = snapshot.data ?? [];

        final startUtc = _selectedDateRange!.start.toUtc();
        final endUtc = _selectedDateRange!.end.add(const Duration(hours: 23, minutes: 59, seconds: 59)).toUtc();

        final periodOrders = allOrders.where((o) {
          final createdAt = DateTime.parse(o['created_at']).toUtc();
          return createdAt.isAfter(startUtc) && createdAt.isBefore(endUtc);
        }).toList();

        final delivered = periodOrders.where((o) => o['status'] == 'Доставлено');
        final revenue = delivered.fold(0.0, (sum, o) => sum + (o['total_amount'] as num));
        final canceled = periodOrders.where((o) => o['status'] == 'Скасовано');

        return ListView(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 100),
          children: [

            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: _isLoadingSettings
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.settings_suggest, color: Color(0xFF005BBB)),
                          SizedBox(width: 8),
                          Text('Тарифи доставки', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                      IconButton(
                        onPressed: _showEditSettingsDialog,
                        icon: const Icon(Icons.edit, color: Color(0xFF005BBB)),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      )
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Базова (подача)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${_basePrice.toStringAsFixed(0)} ₴', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.grey[300]),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('За кожен 1 км', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${_pricePerKm.toStringAsFixed(0)} ₴', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF005BBB))),
                          ],
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(label: const Text('Сьогодні', style: TextStyle(fontWeight: FontWeight.bold)), selected: _selectedDays == 1, onSelected: (_) => _setQuickFilter(1), selectedColor: const Color(0xFF005BBB), labelStyle: TextStyle(color: _selectedDays == 1 ? Colors.white : Colors.black87), backgroundColor: Colors.white.withOpacity(0.9), side: BorderSide.none),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('7 днів', style: TextStyle(fontWeight: FontWeight.bold)), selected: _selectedDays == 7, onSelected: (_) => _setQuickFilter(7), selectedColor: const Color(0xFF005BBB), labelStyle: TextStyle(color: _selectedDays == 7 ? Colors.white : Colors.black87), backgroundColor: Colors.white.withOpacity(0.9), side: BorderSide.none),
                  const SizedBox(width: 8),
                  ChoiceChip(label: const Text('30 днів', style: TextStyle(fontWeight: FontWeight.bold)), selected: _selectedDays == 30, onSelected: (_) => _setQuickFilter(30), selectedColor: const Color(0xFF005BBB), labelStyle: TextStyle(color: _selectedDays == 30 ? Colors.white : Colors.black87), backgroundColor: Colors.white.withOpacity(0.9), side: BorderSide.none),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Календар'),
                    avatar: const Icon(Icons.calendar_month, size: 18),
                    backgroundColor: _selectedDays == 0 ? const Color(0xFF005BBB).withOpacity(0.2) : Colors.white.withOpacity(0.9),
                    side: BorderSide.none,
                    onPressed: _pickDateRange,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20, left: 4),
              child: Text(
                _selectedDateRange!.start == _selectedDateRange!.end
                    ? 'Період: ${_formatDate(_selectedDateRange!.start)}'
                    : 'Період: ${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
              ),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF005BBB), Colors.blue[400]!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Загальна виручка платформи', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text('${revenue.toStringAsFixed(0)} ₴', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delivery_dining, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('Разом із доставкою', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _buildInfoCard('Успішні\nдоставки', delivered.length.toString(), Icons.check_circle, Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _buildInfoCard('Скасовані\nзамовлення', canceled.length.toString(), Icons.cancel, Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: _buildInfoCard('Активні\nзаклади', _restaurantCount.toString(), Icons.storefront, const Color(0xFF005BBB))),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}

// ============================================================================
// ВКЛАДКА 2: УПРАВЛІННЯ РЕСТОРАНАМИ
// ============================================================================
class AdminRestaurantsTab extends StatefulWidget {
  const AdminRestaurantsTab({super.key});

  @override
  State<AdminRestaurantsTab> createState() => _AdminRestaurantsTabState();
}

class _AdminRestaurantsTabState extends State<AdminRestaurantsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _showRestaurantForm({Map<String, dynamic>? restaurant}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RestaurantFormBottomSheet(restaurant: restaurant),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton.extended(
          onPressed: () => _showRestaurantForm(),
          backgroundColor: const Color(0xFFFFCD00),
          foregroundColor: Colors.black,
          elevation: 4,
          icon: const Icon(Icons.add, size: 24),
          label: const Text('Додати заклад', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.client
            .from('restaurants')
            .stream(primaryKey: ['id'])
            .order('name', ascending: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final restaurants = snapshot.data ?? [];

          if (restaurants.isEmpty) {
            return Center(
              child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                  child: const Text('У вас ще немає підключених закладів', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold))
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 160),
            itemCount: restaurants.length,
            itemBuilder: (context, index) {
              final restaurant = restaurants[index];
              final imageUrl = restaurant['image_url'];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showRestaurantForm(restaurant: restaurant),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                          child: Container(
                            width: 110,
                            height: 110,
                            color: Colors.grey[200],
                            child: imageUrl != null && imageUrl.toString().isNotEmpty
                                ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.store, color: Colors.grey, size: 40))
                                : const Icon(Icons.store, color: Colors.grey, size: 40),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(restaurant['name'] ?? 'Невідомо', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.category, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(restaurant['category'] ?? 'Без категорії', style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.timer, size: 16, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text('~${restaurant['prep_time_minutes'] ?? 20} хв', style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Icon(Icons.edit, color: Color(0xFF005BBB)),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// РОЗУМНА ФОРМА РЕСТОРАНУ
// ============================================================================
class RestaurantFormBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? restaurant;
  const RestaurantFormBottomSheet({super.key, this.restaurant});

  @override
  State<RestaurantFormBottomSheet> createState() => _RestaurantFormBottomSheetState();
}

class _RestaurantFormBottomSheetState extends State<RestaurantFormBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _prepTimeController;

  File? _selectedImage;
  String? _existingImageUrl;
  bool _isLoading = false;

  List<String> _availableCategories = [];
  List<String> _selectedCategories = [];
  bool _isLoadingCategories = true;

  @override
  void initState() {
    super.initState();
    final r = widget.restaurant;
    _nameController = TextEditingController(text: r?['name'] ?? '');
    _addressController = TextEditingController(text: r?['address'] ?? '');
    _prepTimeController = TextEditingController(text: (r?['prep_time_minutes'] ?? 20).toString());
    _existingImageUrl = r?['image_url'];

    final existingCats = r?['category']?.toString() ?? '';
    if (existingCats.isNotEmpty) {
      _selectedCategories = existingCats.split(',').map((e) => e.trim()).toList();
    }

    _fetchCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _prepTimeController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await SupabaseService.client.from('categories').select('name');
      if (mounted) {
        setState(() {
          _availableCategories = res.map<String>((c) => c['name'].toString()).toList();
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Помилка завантаження категорій: $e');
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _showCategoryPicker() async {
    List<String> tempSelected = List.from(_selectedCategories);

    await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('Виберіть категорії', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: _isLoadingCategories
                        ? const Center(child: CircularProgressIndicator())
                        : _availableCategories.isEmpty
                        ? const Text('У базі немає категорій. Створіть їх у таблиці categories.')
                        : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _availableCategories.length,
                      itemBuilder: (context, index) {
                        final cat = _availableCategories[index];
                        final isSelected = tempSelected.contains(cat);

                        return CheckboxListTile(
                          title: Text(cat, style: const TextStyle(fontWeight: FontWeight.w600)),
                          value: isSelected,
                          activeColor: const Color(0xFF005BBB),
                          onChanged: (bool? val) {
                            setDialogState(() {
                              if (val == true) {
                                tempSelected.add(cat);
                              } else {
                                tempSelected.remove(cat);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Скасувати', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005BBB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () {
                        setState(() {
                          _selectedCategories = tempSelected;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Застосувати', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveRestaurant() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оберіть хоча б одну категорію!'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? finalImageUrl = _existingImageUrl;

      if (_selectedImage != null) {
        final fileExt = _selectedImage!.path.split('.').last;
        final fileName = 'rest_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

        await SupabaseService.client.storage
            .from('restaurant_images')
            .upload(fileName, _selectedImage!);

        finalImageUrl = SupabaseService.client.storage
            .from('restaurant_images')
            .getPublicUrl(fileName);
      }

      final data = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'category': _selectedCategories.join(', '),
        'prep_time_minutes': int.tryParse(_prepTimeController.text.trim()) ?? 20,
        'image_url': finalImageUrl,
      };

      if (widget.restaurant == null) {
        await SupabaseService.client.from('restaurants').insert(data);
      } else {
        await SupabaseService.client.from('restaurants').update(data).eq('id', widget.restaurant!['id'].toString());
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дані успішно збережено! ✅'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.restaurant != null;

    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),

              Text(isEditing ? 'Редагувати заклад' : 'Новий заклад', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 160, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF005BBB).withOpacity(0.3), width: 2)),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.cover)
                      : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                      ? Image.network(_existingImageUrl!, fit: BoxFit.cover)
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: 40, color: const Color(0xFF005BBB).withOpacity(0.5)),
                      const SizedBox(height: 8),
                      Text('Натисніть, щоб обрати фото', style: TextStyle(color: const Color(0xFF005BBB).withOpacity(0.8), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Назва ресторану', prefixIcon: const Icon(Icons.store, color: Color(0xFF005BBB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true, fillColor: Colors.grey[50]),
                validator: (val) => val == null || val.isEmpty ? 'Введіть назву' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(labelText: 'Адреса закладу', prefixIcon: const Icon(Icons.location_on, color: Color(0xFF005BBB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true, fillColor: Colors.grey[50]),
                validator: (val) => val == null || val.isEmpty ? 'Введіть адресу' : null,
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _showCategoryPicker,
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: 'Категорії',
                      prefixIcon: const Icon(Icons.category, color: Color(0xFF005BBB)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true, fillColor: Colors.grey[50]
                  ),
                  child: Text(
                    _selectedCategories.isEmpty ? 'Натисніть, щоб обрати' : _selectedCategories.join(', '),
                    style: TextStyle(color: _selectedCategories.isEmpty ? Colors.grey[500] : Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _prepTimeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Середній час приготування (хв)', prefixIcon: const Icon(Icons.timer, color: Color(0xFF005BBB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), filled: true, fillColor: Colors.grey[50]),
                validator: (val) => val == null || val.isEmpty ? 'Введіть час' : null,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCD00), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
                  onPressed: _isLoading ? null : _saveRestaurant,
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text(isEditing ? 'Зберегти зміни' : 'Створити заклад', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ВКЛАДКА 3: МОНІТОРИНГ КУР'ЄРІВ (АКТИВНІ ДОСТАВКИ)
// ============================================================================
class AdminCouriersTab extends StatelessWidget {
  const AdminCouriersTab({super.key});

  Future<String> _getCourierName(String? courierId) async {
    if (courierId == null) return 'Не призначено';
    try {
      final profile = await SupabaseService.client.from('profiles').select('full_name').eq('user_id', courierId).maybeSingle();
      return profile?['full_name'] ?? 'Невідомий кур\'єр';
    } catch (e) {
      return 'Кур\'єр';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        final allOrders = snapshot.data ?? [];
        final activeDeliveries = allOrders.where((o) =>
        o['status'] == 'Готується' ||
            o['status'] == 'Готово до видачі' ||
            o['status'] == 'В дорозі' ||
            o['status'] == 'Прибув до місця'
        ).toList();

        if (activeDeliveries.isEmpty) {
          return Center(
            child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                child: const Text('Зараз немає активних доставок 🛵', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 120),
          itemCount: activeDeliveries.length,
          itemBuilder: (context, index) {
            final order = activeDeliveries[index];
            final bool hasCourier = order['courier_id'] != null;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Замовлення #${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text(order['status'], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    FutureBuilder<String>(
                        future: _getCourierName(order['courier_id']),
                        builder: (context, snapshot) {
                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: hasCourier ? Colors.deepPurple.withOpacity(0.1) : Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                                child: Icon(Icons.moped, color: hasCourier ? Colors.deepPurple : Colors.orange, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(hasCourier ? 'Кур\'єр призначений:' : 'Шукаємо кур\'єра...', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    Text(snapshot.data ?? 'Завантаження...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: hasCourier ? Colors.black87 : Colors.orange)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Куди: ${order['delivery_address'] ?? 'Не вказано'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// ВКЛАДКА 4: БАЗА КЛІЄНТІВ
// ============================================================================
class AdminClientsTab extends StatefulWidget {
  const AdminClientsTab({super.key});

  @override
  State<AdminClientsTab> createState() => _AdminClientsTabState();
}

class _AdminClientsTabState extends State<AdminClientsTab> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _allProfiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchClients();
  }

  Future<void> _fetchClients() async {
    try {
      final data = await SupabaseService.client.from('profiles').select().order('full_name');
      if (mounted) {
        setState(() {
          _allProfiles = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Помилка завантаження клієнтів: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _allProfiles.where((p) {
      final name = (p['full_name'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 16),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Пошук за ім\'ям або телефоном...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF005BBB)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.95),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredProfiles.isEmpty
              ? Center(
              child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Клієнтів не знайдено 🕵️‍♂️', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
              )
          )
              : ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 120),
            itemCount: filteredProfiles.length,
            itemBuilder: (context, index) {
              final profile = filteredProfiles[index];
              final hasCity = profile['city'] != null && profile['city'].toString().isNotEmpty;
              final hasAddress = profile['address'] != null && profile['address'].toString().isNotEmpty;

              return Container(
                margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF005BBB).withOpacity(0.1),
                    child: const Icon(Icons.person, color: Color(0xFF005BBB)),
                  ),
                  title: Text(profile['full_name'] ?? 'Без імені', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(profile['phone'] ?? 'Немає телефону', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                      if (hasCity || hasAddress) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                            const SizedBox(width: 4),
                            Expanded(child: Text('${profile['city'] ?? ''} ${profile['address'] ?? ''}', style: const TextStyle(fontSize: 12))),
                          ],
                        )
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}