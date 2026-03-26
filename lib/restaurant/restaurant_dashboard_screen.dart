import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../core/supabase_service.dart';
import '../screens/auth/auth_gate.dart';
import '../providers/theme_provider.dart';

import 'orders_list_tab.dart';
import 'menu_management_tab.dart';
import 'statistics_tab.dart';

class RestaurantDashboardScreen extends StatefulWidget {
  final dynamic restaurantId;
  const RestaurantDashboardScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantDashboardScreen> createState() => _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isRestaurantOpen = true;
  bool _isPeakHours = false;

  String _openTime = '10:00';
  String _closeTime = '22:00';

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _repeatTimer;
  bool _hasNewOrders = false;
  late AnimationController _bellController;
  late Animation<double> _bellAnimation;
  bool _isShiftActive = false;
  final Map<String, String> _previousOrderStatuses = {};

  StreamSubscription? _orderListenerSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bellController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _bellAnimation = Tween<double>(begin: -0.2, end: 0.2).animate(_bellController);
    _fetchRestaurantStatus();
    _setupOrderListener();
    _checkShiftStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setupOrderListener();
      _fetchRestaurantStatus();
    }
  }

  Future<void> _checkShiftStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _isShiftActive = prefs.getBool('shift_restaurant_${widget.restaurantId}') ?? false);
  }

  Future<void> _toggleShift(bool isActive) async {
    final prefs = await SharedPreferences.getInstance();
    final topic = 'restaurant_${widget.restaurantId}';

    if (isActive) {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      await prefs.setBool('shift_restaurant_${widget.restaurantId}', true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🟢 Зміну розпочато!'), backgroundColor: Colors.green));
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      await prefs.setBool('shift_restaurant_${widget.restaurantId}', false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔴 Зміну завершено.'), backgroundColor: Colors.orange));
    }
    setState(() => _isShiftActive = isActive);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orderListenerSub?.cancel();
    _stopAlarm();
    _audioPlayer.dispose();
    _bellController.dispose();
    super.dispose();
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('audio/notification.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('Помилка звуку: $e');
    }
  }

  void _setupOrderListener() {
    _orderListenerSub?.cancel();
    _orderListenerSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', widget.restaurantId)
        .listen((List<Map<String, dynamic>> allData) {

      // 🔥 1. СИРЕНА ДЛЯ НОВИХ НЕОПЛАЧЕНИХ ЗАМОВЛЕНЬ
      final newOrders = allData.where((order) => order['status'] == 'Очікує підтвердження').toList();

      if (newOrders.isNotEmpty) {
        if (!_hasNewOrders) {
          setState(() => _hasNewOrders = true);
          _startAlarm();
        }
      } else {
        if (_hasNewOrders) {
          setState(() => _hasNewOrders = false);
          _stopAlarm();
        }
      }

      // 🔥 2. ВІДСТЕЖЕННЯ ОПЛАТИ ВІД КЛІЄНТА
      for (var order in allData) {
        final id = order['id'].toString();
        final currentStatus = order['status'];
        final previousStatus = _previousOrderStatuses[id];

        if (previousStatus != null && previousStatus != currentStatus) {

          // А) Клієнт успішно ОПЛАТИВ замовлення (Вебхук змінив статус на Готується)
          if (previousStatus == 'Очікує оплати' && currentStatus == 'Готується') {
            _playNotificationSound();
            if (mounted) {
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    backgroundColor: Colors.green[50],
                    title: const Row(children: [Icon(Icons.monetization_on, color: Colors.green, size: 35), SizedBox(width: 10), Text('ОПЛАЧЕНО!', style: TextStyle(color: Colors.green))]),
                    content: Text('Клієнт успішно оплатив замовлення №${id.substring(0, 5)}.\n\nМОЖНА ПОЧИНАТИ ГОТУВАТИ!', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    actions: [ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text('В роботу'))],
                  ));
            }
          }
          // Б) Клієнт ВІДМОВИВСЯ від оплати (Скасував)
          else if (currentStatus == 'Скасовано' && previousStatus == 'Очікує оплати') {
            _playNotificationSound();
            if (mounted) {
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    // 🔥 ВИПРАВЛЕНО: Синтаксис та захист від переповнення (Flexible)
                    title: const Row(
                      children: [
                        Icon(Icons.cancel, color: Colors.red),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Скасовано клієнтом',
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                    content: Text('Клієнт відмовився від замовлення №${id.substring(0, 5)}.\n\n${order['cancellation_reason'] ?? 'Готувати не потрібно.'}', style: const TextStyle(fontSize: 16)),
                    actions: [ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Закрити'))],
                  ));
            }
          }
        }

        _previousOrderStatuses[id] = currentStatus;
      }
    });
  }

  void _startAlarm() {
    _stopAlarm();
    _playNotificationSound();
    _bellController.repeat(reverse: true);
    _repeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_hasNewOrders) _playNotificationSound(); else _stopAlarm();
    });
  }

  void _stopAlarm() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _bellController.stop();
    _bellController.reset();
  }

  Future<void> _fetchRestaurantStatus() async {
    try {
      final res = await SupabaseService.client
          .from('restaurants')
          .select('is_open, is_peak_hours, open_time, close_time')
          .eq('id', widget.restaurantId)
          .single();

      if (mounted) {
        setState(() {
          _isRestaurantOpen = res['is_open'] ?? true;
          _isPeakHours = res['is_peak_hours'] ?? false;
          _openTime = res['open_time'] ?? '10:00';
          _closeTime = res['close_time'] ?? '22:00';
        });
      }
    } catch (e) {
      debugPrint('Помилка статусу: $e');
    }
  }

  Future<void> _toggleRestaurantStatus(bool isOpen) async {
    setState(() => _isRestaurantOpen = isOpen);
    try {
      await SupabaseService.client.from('restaurants').update({'is_open': isOpen}).eq('id', widget.restaurantId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isOpen ? 'Відчинено' : 'Зачинено'), backgroundColor: isOpen ? Colors.green : Colors.orange));
    } catch (e) {
      setState(() => _isRestaurantOpen = !isOpen);
    }
  }

  Future<void> _togglePeakHours(bool isPeak) async {
    setState(() => _isPeakHours = isPeak);
    try {
      await SupabaseService.client.from('restaurants').update({'is_peak_hours': isPeak}).eq('id', widget.restaurantId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isPeak ? '🔥 Увімкнено режим високого навантаження' : '✅ Звичайний режим'), backgroundColor: isPeak ? Colors.orange : Colors.green));
    } catch (e) {
      setState(() => _isPeakHours = !isPeak);
    }
  }

  Future<void> _updateRestaurantImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

      if (image == null) return;

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Завантажуємо фото... ⏳')));
      }

      final bytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName = 'rest_${widget.restaurantId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      final bucketName = 'restaurant_images';

      await SupabaseService.client.storage.from(bucketName).uploadBinary(fileName, bytes);
      final imageUrl = SupabaseService.client.storage.from(bucketName).getPublicUrl(fileName);

      await SupabaseService.client.from('restaurants').update({'image_url': imageUrl}).eq('id', widget.restaurantId);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Фото закладу успішно оновлено! 🎉'), backgroundColor: Colors.green));

    } catch (e) {
      debugPrint('Помилка завантаження фото: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка завантаження: $e'), backgroundColor: Colors.red));
    }
  }

  void _showSettingsDialog() {
    String tempOpen = _openTime;
    String tempClose = _closeTime;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blueGrey),
                    SizedBox(width: 10),
                    Text('Налаштування', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? Colors.deepPurple.withOpacity(0.2) : Colors.deepPurple[50],
                              foregroundColor: isDark ? Colors.deepPurple[200] : Colors.deepPurple,
                              elevation: 0,
                              side: BorderSide(color: isDark ? Colors.deepPurple[300]!.withOpacity(0.5) : Colors.deepPurple[200]!),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: _updateRestaurantImage,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Змінити фото закладу', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const Divider(height: 30),

                      const Text('Оформлення', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 10),
                      Consumer<ThemeProvider>(
                        builder: (context, themeProvider, child) {
                          return SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.settings_suggest),
                                label: Text('Авто', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode),
                                label: Text('Світла', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode),
                                label: Text('Темна', style: TextStyle(fontSize: 12)),
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
                      const Divider(height: 30),

                      const Text('Графік роботи ресторану:', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Відкриття:', style: TextStyle(fontSize: 16)),
                          OutlinedButton(
                            onPressed: () async {
                              final initialTime = TimeOfDay(hour: int.parse(tempOpen.split(':')[0]), minute: int.parse(tempOpen.split(':')[1]));
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
                              );
                              if (picked != null) {
                                setDialogState(() => tempOpen = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                              }
                            },
                            child: Text(tempOpen, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Закриття:', style: TextStyle(fontSize: 16)),
                          OutlinedButton(
                            onPressed: () async {
                              final initialTime = TimeOfDay(hour: int.parse(tempClose.split(':')[0]), minute: int.parse(tempClose.split(':')[1]));
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
                              );
                              if (picked != null) {
                                setDialogState(() => tempClose = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                              }
                            },
                            child: Text(tempClose, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Скасувати', style: TextStyle(color: Colors.grey))
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005BBB), foregroundColor: Colors.white),
                    onPressed: () async {
                      try {
                        await SupabaseService.client.from('restaurants').update({
                          'open_time': tempOpen,
                          'close_time': tempClose,
                        }).eq('id', widget.restaurantId);

                        setState(() {
                          _openTime = tempOpen;
                          _closeTime = tempClose;
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Графік успішно оновлено! ⏰'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Зберегти'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.red[800],
          foregroundColor: Colors.white,

          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isRestaurantOpen ? 'Відчинено' : 'Зачинено', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Switch(value: _isRestaurantOpen, onChanged: _toggleRestaurantStatus, activeColor: Colors.greenAccent),
            ],
          ),

          actions: [
            Row(
              children: [
                const Icon(Icons.work, color: Colors.white70, size: 18),
                Switch(value: _isShiftActive, activeColor: Colors.white, activeTrackColor: Colors.green[400], onChanged: _toggleShift),
              ],
            ),
            const SizedBox(width: 4),

            Row(
              children: [
                Icon(Icons.local_fire_department, color: _isPeakHours ? Colors.orangeAccent : Colors.white54, size: 20),
                Switch(value: _isPeakHours, onChanged: _togglePeakHours, activeColor: Colors.orangeAccent),
              ],
            ),

            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) async {
                if (value == 'settings') {
                  _showSettingsDialog();
                } else if (value == 'logout') {
                  if (_isShiftActive) await _toggleShift(false);

                  try {
                    await FirebaseMessaging.instance.deleteToken();
                  } catch (e) {
                    debugPrint('Помилка видалення токена: $e');
                  }

                  await SupabaseService.client.auth.signOut();
                  if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (route) => false);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: ListTile(leading: Icon(Icons.settings), title: Text('Налаштування годин'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(leading: Icon(Icons.logout, color: Colors.red), title: Text('Вийти', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero),
                ),
              ],
            ),
          ],

          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(
                  text: 'Нові',
                  icon: AnimatedBuilder(
                    animation: _bellAnimation,
                    builder: (context, child) => Transform.rotate(angle: _bellAnimation.value, child: Icon(Icons.notifications_active, color: _hasNewOrders ? Colors.yellowAccent : null)),
                  )
              ),
              const Tab(text: 'В роботі', icon: Icon(Icons.soup_kitchen)),
              const Tab(text: 'Історія', icon: Icon(Icons.history)),
              const Tab(text: 'Меню', icon: Icon(Icons.restaurant_menu)),
              const Tab(text: 'Стат', icon: Icon(Icons.bar_chart)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OrdersListTab(statusFilter: 'Очікує підтвердження', restaurantId: widget.restaurantId),
            OrdersListTab(statusFilter: 'В роботі', restaurantId: widget.restaurantId),
            OrdersListTab(statusFilter: 'Історія', restaurantId: widget.restaurantId),
            RestaurantMenuManager(restaurantId: widget.restaurantId),
            RestaurantStatisticsView(restaurantId: widget.restaurantId),
          ],
        ),
      ),
    );
  }
}