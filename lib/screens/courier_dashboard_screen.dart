<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:geocoding/geocoding.dart';

// --- ДОДАНО ДЛЯ FIREBASE ТА ЗБЕРЕЖЕННЯ СТАТУСУ ---
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
// -----------------------------------

import '../../core/supabase_service.dart';
import '../../core/notification_service.dart';
import 'auth/auth_gate.dart';

class CourierDashboardScreen extends StatefulWidget {
  const CourierDashboardScreen({super.key});

  @override
  State<CourierDashboardScreen> createState() => _CourierDashboardScreenState();
}

class _CourierDashboardScreenState extends State<CourierDashboardScreen> {
  final String? _myUserId = SupabaseService.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _availableOrders = [];
  List<Map<String, dynamic>> _myActiveOrders = [];
  bool _isLoadingAvailable = true;
  bool _isLoadingMy = true;

  StreamSubscription? _availableSub;
  StreamSubscription? _myOrdersSub;
  StreamSubscription? _preorderRadarSub;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> _knownAvailableOrderIds = [];

  // ДОДАНО: Для відстеження зміни статусу в МОЇХ замовленнях (щоб програвати звук)
  final Map<String, String> _knownOrderStatuses = {};

  final Set<String> _scheduledCourierPreorderIds = {};

  StreamSubscription<Position>? _positionStreamSub;
  String? _trackingOrderId;

  bool _isShiftActive = false;

  @override
  void initState() {
    super.initState();
    _setupDatabaseListeners();
    _determinePosition();
    _checkShiftStatus();
  }

  Future<void> _checkShiftStatus() async {
    if (_myUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool('shift_courier_$_myUserId') ?? false;

    if (mounted) {
      setState(() {
        _isShiftActive = isActive;
      });
    }
  }

  Future<void> _toggleShift(bool isActive) async {
    if (_myUserId == null) return;

    final prefs = await SharedPreferences.getInstance();

    if (isActive) {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

      // 1. Підписка на загальні виклики
      await FirebaseMessaging.instance.subscribeToTopic('couriers');
      // 2. ДОДАНО: Підписка на особисті сповіщення (коли готове саме ЙОГО замовлення)
      await FirebaseMessaging.instance.subscribeToTopic('courier_$_myUserId');

      await prefs.setBool('shift_courier_$_myUserId', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🟢 Зміну розпочато! Ви будете отримувати нові замовлення.'), backgroundColor: Colors.green),
        );
      }
    } else {
      // Відписуємось від усього
      await FirebaseMessaging.instance.unsubscribeFromTopic('couriers');
      await FirebaseMessaging.instance.unsubscribeFromTopic('courier_$_myUserId');
      await prefs.setBool('shift_courier_$_myUserId', false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔴 Зміну завершено. Сповіщення вимкнено.'), backgroundColor: Colors.orange),
        );
      }
    }
    setState(() {
      _isShiftActive = isActive;
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  void _startLocationTracking(String orderId) async {
    _trackingOrderId = orderId;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);

    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (_trackingOrderId != null) {
        SupabaseService.client.from('orders').update({
          'courier_lat': position.latitude,
          'courier_lng': position.longitude,
        }).eq('id', _trackingOrderId!);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📡 Трансляцію геолокації увімкнено!'), backgroundColor: Colors.purple));
    }
  }

  void _stopLocationTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _trackingOrderId = null;
  }

  void _setupDatabaseListeners() {
    if (_myUserId == null) return;

    _availableSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'Готується') // Вільні замовлення з'являються тільки після оплати!
        .order('created_at', ascending: true)
        .listen((orders) {

      final available = orders.where((o) => o['courier_id'] == null).toList();

      final currentIds = available.map((o) => o['id'].toString()).toList();
      final hasNewOrders = currentIds.any((id) => !_knownAvailableOrderIds.contains(id));

      if (hasNewOrders) {
        _playNotificationSound();
      }
      _knownAvailableOrderIds = currentIds;

      if (mounted) {
        setState(() {
          _availableOrders = available;
          _isLoadingAvailable = false;
        });
      }
    });

    _myOrdersSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('courier_id', _myUserId!)
        .order('created_at', ascending: true)
        .listen((orders) {

      final active = orders.where((o) =>
      o['status'] == 'Готується' ||
          o['status'] == 'Готово до видачі' ||
          o['status'] == 'В дорозі' ||
          o['status'] == 'Прибув до місця'
      ).toList();

      // ПЕРЕВІРКА НА ЗМІНУ СТАТУСУ (для звуку)
      bool hasReadyOrder = false;
      for (var o in active) {
        final id = o['id'].toString();
        final status = o['status'];

        // Якщо раніше було не готове, а тепер готове — граємо звук!
        if (_knownOrderStatuses[id] != 'Готово до видачі' && status == 'Готово до видачі') {
          hasReadyOrder = true;
        }
        _knownOrderStatuses[id] = status; // Оновлюємо пам'ять
      }

      if (hasReadyOrder) {
        _playNotificationSound();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔔 Ресторан приготував замовлення! Забирайте!'),
                backgroundColor: Colors.teal,
                duration: Duration(seconds: 5),
              )
          );
        }
      }

      if (mounted) {
        setState(() {
          _myActiveOrders = active;
          _isLoadingMy = false;
        });
      }
    });

    _preorderRadarSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen((orders) {

      for (var order in orders) {
        if (order['status'] == 'Скасовано' || order['status'] == 'Доставлено') continue;

        final String orderId = order['id'].toString();

        if (order['desired_delivery_time'] != null && !_scheduledCourierPreorderIds.contains(orderId)) {
          _scheduledCourierPreorderIds.add(orderId);

          final desiredTime = DateTime.parse(order['desired_delivery_time']).toLocal();
          final reminderTime = desiredTime.subtract(const Duration(minutes: 45));
          final now = DateTime.now();

          if (reminderTime.isAfter(now)) {
            final shortId = orderId.substring(0, 5);
            final timeString = '${desiredTime.hour.toString().padLeft(2, '0')}:${desiredTime.minute.toString().padLeft(2, '0')}';

            NotificationService().scheduleNotification(
              id: orderId.hashCode + 3000,
              title: '🛵 Увага! Скоро попереднє замовлення!',
              body: 'Замовлення №$shortId на $timeString. Готуйтеся забирати його з ресторану.',
              delayMinutes: reminderTime.difference(now).inMinutes,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _availableSub?.cancel();
    _myOrdersSub?.cancel();
    _preorderRadarSub?.cancel();
    _audioPlayer.dispose();
    _positionStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/notification.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('Помилка відтворення звуку курєра: $e');
    }
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    try {
      final response = await SupabaseService.client
          .from('orders')
          .update({'courier_id': _myUserId})
          .eq('id', order['id'])
          .filter('courier_id', 'is', null)
          .select();

      if (response.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Хтось інший вже забрав це замовлення! 🏃‍♂️'), backgroundColor: Colors.orange));
        return;
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Замовлення успішно закріплено за вами! 🛵'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      await SupabaseService.client.from('orders').update({'status': newStatus}).eq('id', orderId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Статус оновлено: $newStatus'), backgroundColor: Colors.blue));

      if (newStatus == 'В дорозі') {
        _startLocationTracking(orderId);
      } else if (newStatus == 'Доставлено' || newStatus == 'Скасовано') {
        _stopLocationTracking();
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<String> _getRestaurantName(String resId) async {
    try {
      final res = await SupabaseService.client.from('restaurants').select('name').eq('id', resId).single();
      return res['name'] ?? 'Невідомий ресторан';
    } catch (e) {
      return 'Ресторан';
    }
  }

  Future<void> _openNavigation(String address) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Шукаємо координати... 🌍'), duration: Duration(seconds: 1)));
      List<Location> locations = await locationFromAddress(address);
      if (locations.isEmpty) throw Exception('Адресу не знайдено');

      final lat = locations.first.latitude;
      final lng = locations.first.longitude;

      final availableMaps = await MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не знайдено жодного навігатора на телефоні! 🚫')));
        return;
      }

      if (mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (BuildContext context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(padding: EdgeInsets.all(16.0), child: Text('Оберіть навігатор', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ...availableMaps.map((map) => ListTile(
                    onTap: () {
                      map.showDirections(destination: Coords(lat, lng), destinationTitle: address);
                      Navigator.pop(context);
                    },
                    leading: const Icon(Icons.map, color: Colors.blue),
                    title: Text('Відкрити у ${map.mapName}'),
                  )),
                ],
              ),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не вдалося побудувати маршрут. Перевірте адресу.'), backgroundColor: Colors.red));
    }
  }
// ==========================================================================
  // ДОДАНО: ВІКНО ПРОФІЛЮ КУР'ЄРА
  // ==========================================================================
  Future<void> _showProfileDialog() async {
    final nameController = TextEditingController();
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await SupabaseService.client
          .from('profiles')
          .select('full_name')
          .eq('user_id', user.id)
          .maybeSingle();
      nameController.text = profile?['full_name'] ?? '';
    } catch (e) {
      debugPrint('Помилка завантаження профілю: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.person, color: Colors.deepPurple),
                    SizedBox(width: 10),
                    Text('Мій профіль'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Це ім\'я будуть бачити клієнти та ресторани:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Ваше Ім\'я',
                        prefixIcon: const Icon(Icons.badge, color: Colors.deepPurple),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Скасувати', style: TextStyle(color: Colors.grey))
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                    onPressed: isSaving ? null : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        await SupabaseService.client.from('profiles').upsert({
                          'user_id': user.id,
                          'phone': user.phone,
                          'full_name': nameController.text.trim(),
                        });
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профіль оновлено! 🎉'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                      } finally {
                        setDialogState(() => isSaving = false);
                      }
                    },
                    child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Зберегти'),
                  ),
                ],
              );
            }
        );
      },
    );
  }
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (_myUserId == null) return const Scaffold(body: Center(child: Text('Помилка авторизації')));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Термінал', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _isShiftActive ? Colors.green[700] : Colors.deepPurple,
          foregroundColor: Colors.white,
          actions: [
            Row(
              children: [
                Text(_isShiftActive ? 'НА ЗМІНІ' : 'ОФЛАЙН', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Switch(
                  value: _isShiftActive,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.green[400],
                  inactiveThumbColor: Colors.grey[300],
                  inactiveTrackColor: Colors.white30,
                  onChanged: (val) => _toggleShift(val),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Профіль',
              onPressed: _showProfileDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Вийти',
              onPressed: () async {
                if (_isShiftActive) await _toggleShift(false);

                try {
                  await FirebaseMessaging.instance.deleteToken();
                } catch (e) {
                  debugPrint('Помилка видалення токена Firebase: $e');
                }

                await SupabaseService.client.auth.signOut();
                if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false);
              },
            )
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'ЕФІР (Вільні)', icon: Icon(Icons.radar)),
              Tab(text: 'МОЇ ДОСТАВКИ', icon: Icon(Icons.moped)),
            ],
          ),
        ),

        body: Container(
          color: Colors.grey[100],
          child: TabBarView(
            children: [
              _isLoadingAvailable
                  ? const Center(child: CircularProgressIndicator())
                  : _availableOrders.isEmpty
                  ? const Center(child: Text('Поки немає вільних замовлень', style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _availableOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(_availableOrders[index], isAvailable: true),
              ),

              _isLoadingMy
                  ? const Center(child: CircularProgressIndicator())
                  : _myActiveOrders.isEmpty
                  ? const Center(child: Text('У вас немає активних доставок', style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _myActiveOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(_myActiveOrders[index], isAvailable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {required bool isAvailable}) {
    final bool isPreorder = order['desired_delivery_time'] != null;
    String preorderTimeStr = '';
    if (isPreorder) {
      final dt = DateTime.parse(order['desired_delivery_time']).toLocal();
      preorderTimeStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} о ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: order['status'] == 'Готово до видачі' ? Colors.teal : (isAvailable ? Colors.deepPurple.withOpacity(0.5) : Colors.blue.withOpacity(0.5)),
            width: order['status'] == 'Готово до видачі' ? 3 : 2
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPreorder)
            Container(
              width: double.infinity,
              color: Colors.purple[100],
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(child: Text('НА ЧАС: $preorderTimeStr', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 15))),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // 🔥 ВИПРАВЛЕНО: Захист від переповнення статусу
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('№ ${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    const Spacer(),
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: order['status'] == 'Готово до видачі' ? Colors.teal[100] : (isAvailable ? Colors.green[100] : Colors.blue[100]),
                            borderRadius: BorderRadius.circular(12)
                        ),
                        child: Text(
                            isAvailable ? 'Вільне' : order['status'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, color: order['status'] == 'Готово до видачі' ? Colors.teal[800] : (isAvailable ? Colors.green[800] : Colors.blue[800]))
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                FutureBuilder<String>(
                    future: _getRestaurantName(order['restaurant_id'].toString()),
                    builder: (context, snapshot) {
                      return Row(
                        children: [
                          const Icon(Icons.storefront, color: Colors.deepPurple),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Звідки: ${snapshot.data ?? 'Завантаження...'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        ],
                      );
                    }
                ),
                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Куди: ${order['delivery_address'] ?? 'Не вказано'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () => _openNavigation(order['delivery_address'] ?? ''),
                            icon: const Icon(Icons.navigation, size: 18),
                            label: const Text('Маршрут'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue[700],
                              side: BorderSide(color: Colors.blue[200]!),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Row(children: [const Icon(Icons.person, size: 18), const SizedBox(width: 8), Expanded(child: Text('${order['receiver_name'] ?? 'Клієнт'}', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                      const SizedBox(height: 4),
                      Row(children: [const Icon(Icons.phone, size: 18), const SizedBox(width: 8), Expanded(child: Text('${order['receiver_phone'] ?? 'Немає номеру'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                      if (order['delivery_comment'] != null && order['delivery_comment'].toString().trim().isNotEmpty) ...[
                        const Divider(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment, size: 18, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${order['delivery_comment']}', style: const TextStyle(fontStyle: FontStyle.italic))),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),

                if (order['status'] == 'Готується' && order['prep_time_minutes'] != null && !isPreorder)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer, color: Colors.orange),
                        const SizedBox(width: 8),
                        Flexible(
                          child: CourierCountdownTimer(
                              createdAt: order['created_at'],
                              prepTimeMinutes: int.tryParse(order['prep_time_minutes'].toString()) ?? 20
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // 🔥 ВИПРАВЛЕНО: Захист тексту кнопок від переповнення (FittedBox)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Builder(
                    builder: (context) {
                      if (isAvailable) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _acceptOrder(order),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ПРИЙНЯТИ ЗАМОВЛЕННЯ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }

                      if (order['status'] == 'Готується' || order['status'] == 'Готово до видачі') {
                        final isReady = order['status'] == 'Готово до видачі';
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isReady ? Colors.teal : Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: () => _updateStatus(order['id'].toString(), 'В дорозі'),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(isReady ? 'ЗАМОВЛЕННЯ ГОТОВЕ! ЗАБРАТИ 🏃‍♂️' : 'Я ЗАБРАВ З РЕСТОРАНУ 🛵', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }
                      else if (order['status'] == 'В дорозі') {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _updateStatus(order['id'].toString(), 'Прибув до місця'),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ПРИБУВ ДО МІСЦЯ 📍', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }
                      else {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _updateStatus(order['id'].toString(), 'Доставлено'),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ДОСТАВЛЕНО КЛІЄНТУ ✅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CourierCountdownTimer extends StatefulWidget {
  final String createdAt;
  final int prepTimeMinutes;

  const CourierCountdownTimer({super.key, required this.createdAt, required this.prepTimeMinutes});

  @override
  State<CourierCountdownTimer> createState() => _CourierCountdownTimerState();
}

class _CourierCountdownTimerState extends State<CourierCountdownTimer> {
  Timer? _timer;
  late DateTime _targetTime;
  String _timeLeft = '';

  @override
  void initState() {
    super.initState();
    _calculateTargetTime();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
  }

  void _calculateTargetTime() {
    DateTime created = DateTime.parse(widget.createdAt).toLocal();
    _targetTime = created.add(Duration(minutes: widget.prepTimeMinutes));
  }

  void _updateTime() {
    final now = DateTime.now();
    final difference = _targetTime.difference(now);

    if (difference.isNegative) {
      if (mounted) setState(() => _timeLeft = 'Страва вже готова! Забирайте!');
      _timer?.cancel();
    } else {
      final minutes = difference.inMinutes.toString().padLeft(2, '0');
      final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _timeLeft = 'Бути в ресторані через: $minutes:$seconds');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeLeft,
      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900], fontSize: 15),
    );
  }
=======
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:geocoding/geocoding.dart';

// --- ДОДАНО ДЛЯ FIREBASE ТА ЗБЕРЕЖЕННЯ СТАТУСУ ---
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
// -----------------------------------

import '../../core/supabase_service.dart';
import '../../core/notification_service.dart';
import 'auth/auth_gate.dart';

class CourierDashboardScreen extends StatefulWidget {
  const CourierDashboardScreen({super.key});

  @override
  State<CourierDashboardScreen> createState() => _CourierDashboardScreenState();
}

class _CourierDashboardScreenState extends State<CourierDashboardScreen> {
  final String? _myUserId = SupabaseService.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _availableOrders = [];
  List<Map<String, dynamic>> _myActiveOrders = [];
  bool _isLoadingAvailable = true;
  bool _isLoadingMy = true;

  StreamSubscription? _availableSub;
  StreamSubscription? _myOrdersSub;
  StreamSubscription? _preorderRadarSub;

  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> _knownAvailableOrderIds = [];

  // ДОДАНО: Для відстеження зміни статусу в МОЇХ замовленнях (щоб програвати звук)
  final Map<String, String> _knownOrderStatuses = {};

  final Set<String> _scheduledCourierPreorderIds = {};

  StreamSubscription<Position>? _positionStreamSub;
  String? _trackingOrderId;

  bool _isShiftActive = false;

  @override
  void initState() {
    super.initState();
    _setupDatabaseListeners();
    _determinePosition();
    _checkShiftStatus();
  }

  Future<void> _checkShiftStatus() async {
    if (_myUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool('shift_courier_$_myUserId') ?? false;

    if (mounted) {
      setState(() {
        _isShiftActive = isActive;
      });
    }
  }

  Future<void> _toggleShift(bool isActive) async {
    if (_myUserId == null) return;

    final prefs = await SharedPreferences.getInstance();

    if (isActive) {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

      // 1. Підписка на загальні виклики
      await FirebaseMessaging.instance.subscribeToTopic('couriers');
      // 2. ДОДАНО: Підписка на особисті сповіщення (коли готове саме ЙОГО замовлення)
      await FirebaseMessaging.instance.subscribeToTopic('courier_$_myUserId');

      await prefs.setBool('shift_courier_$_myUserId', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🟢 Зміну розпочато! Ви будете отримувати нові замовлення.'), backgroundColor: Colors.green),
        );
      }
    } else {
      // Відписуємось від усього
      await FirebaseMessaging.instance.unsubscribeFromTopic('couriers');
      await FirebaseMessaging.instance.unsubscribeFromTopic('courier_$_myUserId');
      await prefs.setBool('shift_courier_$_myUserId', false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔴 Зміну завершено. Сповіщення вимкнено.'), backgroundColor: Colors.orange),
        );
      }
    }
    setState(() {
      _isShiftActive = isActive;
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  void _startLocationTracking(String orderId) async {
    _trackingOrderId = orderId;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);

    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (_trackingOrderId != null) {
        SupabaseService.client.from('orders').update({
          'courier_lat': position.latitude,
          'courier_lng': position.longitude,
        }).eq('id', _trackingOrderId!);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📡 Трансляцію геолокації увімкнено!'), backgroundColor: Colors.purple));
    }
  }

  void _stopLocationTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
    _trackingOrderId = null;
  }

  void _setupDatabaseListeners() {
    if (_myUserId == null) return;

    _availableSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'Готується') // Вільні замовлення з'являються тільки після оплати!
        .order('created_at', ascending: true)
        .listen((orders) {

      final available = orders.where((o) => o['courier_id'] == null).toList();

      final currentIds = available.map((o) => o['id'].toString()).toList();
      final hasNewOrders = currentIds.any((id) => !_knownAvailableOrderIds.contains(id));

      if (hasNewOrders) {
        _playNotificationSound();
      }
      _knownAvailableOrderIds = currentIds;

      if (mounted) {
        setState(() {
          _availableOrders = available;
          _isLoadingAvailable = false;
        });
      }
    });

    _myOrdersSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('courier_id', _myUserId!)
        .order('created_at', ascending: true)
        .listen((orders) {

      final active = orders.where((o) =>
      o['status'] == 'Готується' ||
          o['status'] == 'Готово до видачі' ||
          o['status'] == 'В дорозі' ||
          o['status'] == 'Прибув до місця'
      ).toList();

      // ПЕРЕВІРКА НА ЗМІНУ СТАТУСУ (для звуку)
      bool hasReadyOrder = false;
      for (var o in active) {
        final id = o['id'].toString();
        final status = o['status'];

        // Якщо раніше було не готове, а тепер готове — граємо звук!
        if (_knownOrderStatuses[id] != 'Готово до видачі' && status == 'Готово до видачі') {
          hasReadyOrder = true;
        }
        _knownOrderStatuses[id] = status; // Оновлюємо пам'ять
      }

      if (hasReadyOrder) {
        _playNotificationSound();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔔 Ресторан приготував замовлення! Забирайте!'),
                backgroundColor: Colors.teal,
                duration: Duration(seconds: 5),
              )
          );
        }
      }

      if (mounted) {
        setState(() {
          _myActiveOrders = active;
          _isLoadingMy = false;
        });
      }
    });

    _preorderRadarSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen((orders) {

      for (var order in orders) {
        if (order['status'] == 'Скасовано' || order['status'] == 'Доставлено') continue;

        final String orderId = order['id'].toString();

        if (order['desired_delivery_time'] != null && !_scheduledCourierPreorderIds.contains(orderId)) {
          _scheduledCourierPreorderIds.add(orderId);

          final desiredTime = DateTime.parse(order['desired_delivery_time']).toLocal();
          final reminderTime = desiredTime.subtract(const Duration(minutes: 45));
          final now = DateTime.now();

          if (reminderTime.isAfter(now)) {
            final shortId = orderId.substring(0, 5);
            final timeString = '${desiredTime.hour.toString().padLeft(2, '0')}:${desiredTime.minute.toString().padLeft(2, '0')}';

            NotificationService().scheduleNotification(
              id: orderId.hashCode + 3000,
              title: '🛵 Увага! Скоро попереднє замовлення!',
              body: 'Замовлення №$shortId на $timeString. Готуйтеся забирати його з ресторану.',
              delayMinutes: reminderTime.difference(now).inMinutes,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _availableSub?.cancel();
    _myOrdersSub?.cancel();
    _preorderRadarSub?.cancel();
    _audioPlayer.dispose();
    _positionStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/notification.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('Помилка відтворення звуку курєра: $e');
    }
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    try {
      final response = await SupabaseService.client
          .from('orders')
          .update({'courier_id': _myUserId})
          .eq('id', order['id'])
          .filter('courier_id', 'is', null)
          .select();

      if (response.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Хтось інший вже забрав це замовлення! 🏃‍♂️'), backgroundColor: Colors.orange));
        return;
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Замовлення успішно закріплено за вами! 🛵'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      await SupabaseService.client.from('orders').update({'status': newStatus}).eq('id', orderId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Статус оновлено: $newStatus'), backgroundColor: Colors.blue));

      if (newStatus == 'В дорозі') {
        _startLocationTracking(orderId);
      } else if (newStatus == 'Доставлено' || newStatus == 'Скасовано') {
        _stopLocationTracking();
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<String> _getRestaurantName(String resId) async {
    try {
      final res = await SupabaseService.client.from('restaurants').select('name').eq('id', resId).single();
      return res['name'] ?? 'Невідомий ресторан';
    } catch (e) {
      return 'Ресторан';
    }
  }

  Future<void> _openNavigation(String address) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Шукаємо координати... 🌍'), duration: Duration(seconds: 1)));
      List<Location> locations = await locationFromAddress(address);
      if (locations.isEmpty) throw Exception('Адресу не знайдено');

      final lat = locations.first.latitude;
      final lng = locations.first.longitude;

      final availableMaps = await MapLauncher.installedMaps;

      if (availableMaps.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не знайдено жодного навігатора на телефоні! 🚫')));
        return;
      }

      if (mounted) {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (BuildContext context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(padding: EdgeInsets.all(16.0), child: Text('Оберіть навігатор', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ...availableMaps.map((map) => ListTile(
                    onTap: () {
                      map.showDirections(destination: Coords(lat, lng), destinationTitle: address);
                      Navigator.pop(context);
                    },
                    leading: const Icon(Icons.map, color: Colors.blue),
                    title: Text('Відкрити у ${map.mapName}'),
                  )),
                ],
              ),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не вдалося побудувати маршрут. Перевірте адресу.'), backgroundColor: Colors.red));
    }
  }
// ==========================================================================
  // ДОДАНО: ВІКНО ПРОФІЛЮ КУР'ЄРА
  // ==========================================================================
  Future<void> _showProfileDialog() async {
    final nameController = TextEditingController();
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await SupabaseService.client
          .from('profiles')
          .select('full_name')
          .eq('user_id', user.id)
          .maybeSingle();
      nameController.text = profile?['full_name'] ?? '';
    } catch (e) {
      debugPrint('Помилка завантаження профілю: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.person, color: Colors.deepPurple),
                    SizedBox(width: 10),
                    Text('Мій профіль'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Це ім\'я будуть бачити клієнти та ресторани:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Ваше Ім\'я',
                        prefixIcon: const Icon(Icons.badge, color: Colors.deepPurple),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Скасувати', style: TextStyle(color: Colors.grey))
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                    onPressed: isSaving ? null : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        await SupabaseService.client.from('profiles').upsert({
                          'user_id': user.id,
                          'phone': user.phone,
                          'full_name': nameController.text.trim(),
                        });
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профіль оновлено! 🎉'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                      } finally {
                        setDialogState(() => isSaving = false);
                      }
                    },
                    child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Зберегти'),
                  ),
                ],
              );
            }
        );
      },
    );
  }
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (_myUserId == null) return const Scaffold(body: Center(child: Text('Помилка авторизації')));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Термінал', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: _isShiftActive ? Colors.green[700] : Colors.deepPurple,
          foregroundColor: Colors.white,
          actions: [
            Row(
              children: [
                Text(_isShiftActive ? 'НА ЗМІНІ' : 'ОФЛАЙН', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Switch(
                  value: _isShiftActive,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.green[400],
                  inactiveThumbColor: Colors.grey[300],
                  inactiveTrackColor: Colors.white30,
                  onChanged: (val) => _toggleShift(val),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Профіль',
              onPressed: _showProfileDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Вийти',
              onPressed: () async {
                if (_isShiftActive) await _toggleShift(false);

                try {
                  await FirebaseMessaging.instance.deleteToken();
                } catch (e) {
                  debugPrint('Помилка видалення токена Firebase: $e');
                }

                await SupabaseService.client.auth.signOut();
                if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false);
              },
            )
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'ЕФІР (Вільні)', icon: Icon(Icons.radar)),
              Tab(text: 'МОЇ ДОСТАВКИ', icon: Icon(Icons.moped)),
            ],
          ),
        ),

        body: Container(
          color: Colors.grey[100],
          child: TabBarView(
            children: [
              _isLoadingAvailable
                  ? const Center(child: CircularProgressIndicator())
                  : _availableOrders.isEmpty
                  ? const Center(child: Text('Поки немає вільних замовлень', style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _availableOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(_availableOrders[index], isAvailable: true),
              ),

              _isLoadingMy
                  ? const Center(child: CircularProgressIndicator())
                  : _myActiveOrders.isEmpty
                  ? const Center(child: Text('У вас немає активних доставок', style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _myActiveOrders.length,
                itemBuilder: (context, index) => _buildOrderCard(_myActiveOrders[index], isAvailable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {required bool isAvailable}) {
    final bool isPreorder = order['desired_delivery_time'] != null;
    String preorderTimeStr = '';
    if (isPreorder) {
      final dt = DateTime.parse(order['desired_delivery_time']).toLocal();
      preorderTimeStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} о ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: order['status'] == 'Готово до видачі' ? Colors.teal : (isAvailable ? Colors.deepPurple.withOpacity(0.5) : Colors.blue.withOpacity(0.5)),
            width: order['status'] == 'Готово до видачі' ? 3 : 2
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPreorder)
            Container(
              width: double.infinity,
              color: Colors.purple[100],
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(child: Text('НА ЧАС: $preorderTimeStr', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 15))),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // 🔥 ВИПРАВЛЕНО: Захист від переповнення статусу
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('№ ${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    const Spacer(),
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: order['status'] == 'Готово до видачі' ? Colors.teal[100] : (isAvailable ? Colors.green[100] : Colors.blue[100]),
                            borderRadius: BorderRadius.circular(12)
                        ),
                        child: Text(
                            isAvailable ? 'Вільне' : order['status'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, color: order['status'] == 'Готово до видачі' ? Colors.teal[800] : (isAvailable ? Colors.green[800] : Colors.blue[800]))
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                FutureBuilder<String>(
                    future: _getRestaurantName(order['restaurant_id'].toString()),
                    builder: (context, snapshot) {
                      return Row(
                        children: [
                          const Icon(Icons.storefront, color: Colors.deepPurple),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Звідки: ${snapshot.data ?? 'Завантаження...'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        ],
                      );
                    }
                ),
                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Куди: ${order['delivery_address'] ?? 'Не вказано'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () => _openNavigation(order['delivery_address'] ?? ''),
                            icon: const Icon(Icons.navigation, size: 18),
                            label: const Text('Маршрут'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue[700],
                              side: BorderSide(color: Colors.blue[200]!),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Row(children: [const Icon(Icons.person, size: 18), const SizedBox(width: 8), Expanded(child: Text('${order['receiver_name'] ?? 'Клієнт'}', style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                      const SizedBox(height: 4),
                      Row(children: [const Icon(Icons.phone, size: 18), const SizedBox(width: 8), Expanded(child: Text('${order['receiver_phone'] ?? 'Немає номеру'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                      if (order['delivery_comment'] != null && order['delivery_comment'].toString().trim().isNotEmpty) ...[
                        const Divider(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment, size: 18, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${order['delivery_comment']}', style: const TextStyle(fontStyle: FontStyle.italic))),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),

                if (order['status'] == 'Готується' && order['prep_time_minutes'] != null && !isPreorder)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer, color: Colors.orange),
                        const SizedBox(width: 8),
                        Flexible(
                          child: CourierCountdownTimer(
                              createdAt: order['created_at'],
                              prepTimeMinutes: int.tryParse(order['prep_time_minutes'].toString()) ?? 20
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // 🔥 ВИПРАВЛЕНО: Захист тексту кнопок від переповнення (FittedBox)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Builder(
                    builder: (context) {
                      if (isAvailable) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _acceptOrder(order),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ПРИЙНЯТИ ЗАМОВЛЕННЯ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }

                      if (order['status'] == 'Готується' || order['status'] == 'Готово до видачі') {
                        final isReady = order['status'] == 'Готово до видачі';
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isReady ? Colors.teal : Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: () => _updateStatus(order['id'].toString(), 'В дорозі'),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(isReady ? 'ЗАМОВЛЕННЯ ГОТОВЕ! ЗАБРАТИ 🏃‍♂️' : 'Я ЗАБРАВ З РЕСТОРАНУ 🛵', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }
                      else if (order['status'] == 'В дорозі') {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _updateStatus(order['id'].toString(), 'Прибув до місця'),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ПРИБУВ ДО МІСЦЯ 📍', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }
                      else {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _updateStatus(order['id'].toString(), 'Доставлено'),
                          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ДОСТАВЛЕНО КЛІЄНТУ ✅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CourierCountdownTimer extends StatefulWidget {
  final String createdAt;
  final int prepTimeMinutes;

  const CourierCountdownTimer({super.key, required this.createdAt, required this.prepTimeMinutes});

  @override
  State<CourierCountdownTimer> createState() => _CourierCountdownTimerState();
}

class _CourierCountdownTimerState extends State<CourierCountdownTimer> {
  Timer? _timer;
  late DateTime _targetTime;
  String _timeLeft = '';

  @override
  void initState() {
    super.initState();
    _calculateTargetTime();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
  }

  void _calculateTargetTime() {
    DateTime created = DateTime.parse(widget.createdAt).toLocal();
    _targetTime = created.add(Duration(minutes: widget.prepTimeMinutes));
  }

  void _updateTime() {
    final now = DateTime.now();
    final difference = _targetTime.difference(now);

    if (difference.isNegative) {
      if (mounted) setState(() => _timeLeft = 'Страва вже готова! Забирайте!');
      _timer?.cancel();
    } else {
      final minutes = difference.inMinutes.toString().padLeft(2, '0');
      final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _timeLeft = 'Бути в ресторані через: $minutes:$seconds');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeLeft,
      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900], fontSize: 15),
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}