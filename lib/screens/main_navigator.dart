import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/notification_service.dart';
import '../providers/cart_provider.dart';
import '../core/supabase_service.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';
import 'restaurant_menu_screen.dart';

class MainNavigator extends StatefulWidget {
  final int initialIndex;
  const MainNavigator({super.key, this.initialIndex = 0});
  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  late int _currentIndex;

  // --- ЛОГІКА СПОВІЩЕНЬ ---
  StreamSubscription? _orderSubscription;
  final Map<String, String> _knownOrderStatuses = {};

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    NotificationService().init();
    _listenToMyOrders();
    _subscribeToMarketingPushes();
    _setupPushNotificationClick();
  }

  Future<void> _subscribeToMarketingPushes() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic('all_users');

      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId != null) {
        // 🔥 Підписка на особистий канал клієнта для тихих пушів від сервера
        await FirebaseMessaging.instance.subscribeToTopic('client_$userId');
        debugPrint('Успішно підписано на особисті пуші: client_$userId');
      }
    } catch (e) {
      debugPrint('Помилка підписки: $e');
    }
  }

  void _listenToMyOrders() {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;

    _orderSubscription = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((List<Map<String, dynamic>> orders) {

      for (var order in orders) {
        final String id = order['id'].toString();
        final String newStatus = order['status'];
        final String shortId = id.substring(0, 5);

        if (_knownOrderStatuses.containsKey(id)) {
          if (_knownOrderStatuses[id] != newStatus) {
            _triggerPushNotification(shortId, newStatus);
          }
        }
        _knownOrderStatuses[id] = newStatus;
      }
    });
  }

  Future<void> _setupPushNotificationClick() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handlePushClick(initialMessage);
      });
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handlePushClick(message);
    });
  }

  Future<void> _handlePushClick(RemoteMessage message) async {
    final data = message.data;

    if (data.containsKey('restaurant_id')) {
      final restaurantId = data['restaurant_id'];

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF005BBB))),
      );

      try {
        final restaurantData = await SupabaseService.client
            .from('restaurants')
            .select()
            .eq('id', restaurantId)
            .single();

        if (!mounted) return;
        Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RestaurantMenuScreen(
              restaurant: restaurantData,
              initialCategory: 'Всі',
              categoryEmojis: const {'Всі': '🍽️'},
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        debugPrint('Помилка відкриття ресторану з пуша: $e');
      }
    }
  }

  // 🔥 ОНОВЛЕНІ ЛОКАЛЬНІ ПУШІ (Синхронізовані з новою логікою оплати)
  void _triggerPushNotification(String shortId, String status) {
    String title = 'Замовлення №$shortId оновлено!';
    String body = 'Поточний статус: $status';

    if (status == 'Очікує оплати') {
      title = '💳 Час оплатити замовлення!';
      body = 'Ресторан підтвердив замовлення. Сплатіть рахунок, щоб кухня почала готувати.';
    } else if (status == 'Готується') {
      title = '👨‍🍳 Кухня прийняла замовлення!';
      body = 'Ваші страви вже почали готувати.';
    } else if (status == 'В дорозі') {
      title = '🛵 Кур\'єр в дорозі!';
      body = 'Ваше замовлення вже мчить до вас.';
    } else if (status == 'Прибув до місця') {
      title = '📍 Кур\'єр прибув!';
      body = 'Кур\'єр чекає на вас за адресою доставки.';
    } else if (status == 'Доставлено') {
      title = '✅ Смачного!';
      body = 'Замовлення успішно доставлено. Дякуємо, що ви з нами!';

      NotificationService().scheduleNotification(
        id: shortId.hashCode + 1000,
        title: 'Як вам їжа? 😋',
        body: 'Після того, як поїсте, не забудьте залишити відгук про замовлення!',
        delayMinutes: 3,
        payload: 'review_order_$shortId',
      );

    } else if (status == 'Скасовано' || status == 'Відхилено') {
      title = '❌ Замовлення скасовано';
      body = 'На жаль, замовлення було скасовано.';
    }

    NotificationService().showNotification(
      id: shortId.hashCode,
      title: title,
      body: body,
    );
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  Widget _buildTabNavigator(int index, Widget rootPage) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => rootPage,
        );
      },
    );
  }

  Widget _buildFloatingNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final Color backgroundColor = isSelected ? const Color(0xFF005BBB) : Colors.transparent;
    final Color contentColor = isSelected ? Colors.white : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 20 : 12,
            vertical: 10
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            badgeCount > 0
                ? Badge(
              label: Text(badgeCount.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
              backgroundColor: Colors.redAccent,
              child: Icon(icon, color: contentColor, size: 26),
            )
                : Icon(icon, color: contentColor, size: 26),

            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  label,
                  style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        final currentNavigator = _navigatorKeys[_currentIndex].currentState;

        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else {
          if (_currentIndex != 0) {
            setState(() => _currentIndex = 0);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, const HomeScreen()),
            _buildTabNavigator(1, const CartScreen()),
            _buildTabNavigator(2, const OrdersScreen()),
            _buildTabNavigator(3, const ProfileScreen()),
          ],
        ),

        bottomNavigationBar: Consumer<CartProvider>(
          builder: (context, cart, child) {
            final count = cart.items.length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildFloatingNavItem(
                          index: 0,
                          icon: _currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
                          label: 'Головна',
                          isSelected: _currentIndex == 0,
                          onTap: () {
                            if (_currentIndex == 0) {
                              _navigatorKeys[0].currentState?.popUntil((route) => route.isFirst);
                            }
                            setState(() => _currentIndex = 0);
                          },
                        ),
                        _buildFloatingNavItem(
                          index: 1,
                          icon: _currentIndex == 1 ? Icons.shopping_cart_rounded : Icons.shopping_cart_outlined,
                          label: 'Кошик',
                          isSelected: _currentIndex == 1,
                          badgeCount: count,
                          onTap: () {
                            if (_currentIndex == 1) {
                              _navigatorKeys[1].currentState?.popUntil((route) => route.isFirst);
                            }
                            setState(() => _currentIndex = 1);
                          },
                        ),
                        _buildFloatingNavItem(
                          index: 2,
                          icon: _currentIndex == 2 ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
                          label: 'Історія',
                          isSelected: _currentIndex == 2,
                          onTap: () {
                            if (_currentIndex == 2) {
                              _navigatorKeys[2].currentState?.popUntil((route) => route.isFirst);
                            }
                            setState(() => _currentIndex = 2);
                          },
                        ),
                        _buildFloatingNavItem(
                          index: 3,
                          icon: _currentIndex == 3 ? Icons.person_rounded : Icons.person_outline_rounded,
                          label: 'Профіль',
                          isSelected: _currentIndex == 3,
                          onTap: () {
                            if (_currentIndex == 3) {
                              _navigatorKeys[3].currentState?.popUntil((route) => route.isFirst);
                            }
                            setState(() => _currentIndex = 3);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}