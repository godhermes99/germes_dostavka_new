import 'dart:async';
import 'package:flutter/material.dart';
import '../core/supabase_service.dart';
import 'client_order_tracking_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  final Set<String> _shownReviewDialogs = {};
  final Set<String> _shownPaymentDialogs = {}; // Трекаємо вікна для оплати

  @override
  void initState() {
    super.initState();
    _setupOrdersStream();
  }

  void _setupOrdersStream() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _subscription = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .listen((data) {
      if (mounted) {
        setState(() {
          _orders = data;
          _isLoading = false;
        });

        _checkForUnratedOrders(data);
      }
    }, onError: (error) {
      debugPrint('Помилка потоку замовлень: $error');
      _recoverDataSilently(user.id);
    });
  }

  Future<void> _recoverDataSilently(String userId) async {
    try {
      final data = await SupabaseService.client
          .from('orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _orders = data;
          _isLoading = false;
        });
        _checkForUnratedOrders(data);
      }
    } catch (e) {
      debugPrint('Помилка тихого відновлення: $e');
    }
  }

  Future<String> _getCourierName(String? courierId) async {
    if (courierId == null || courierId.isEmpty) return 'Шукаємо кур\'єра...';
    try {
      final profile = await SupabaseService.client
          .from('profiles')
          .select('full_name')
          .eq('user_id', courierId)
          .maybeSingle();
      return profile?['full_name'] ?? 'Кур\'єр';
    } catch (e) {
      return 'Кур\'єр';
    }
  }

  void _checkForUnratedOrders(List<Map<String, dynamic>> orders) {
    for (var order in orders) {
      final orderId = order['id'].toString();

      // Діалог відгуку
      if (order['status'] == 'Доставлено' && order['rating'] == null) {
        if (!_shownReviewDialogs.contains(orderId)) {
          _shownReviewDialogs.add(orderId);
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _showReviewDialog(order);
          });
        }
      }

      // 🔥 НОВЕ ВІКНО: Пропозиція оплатити (після підтвердження рестораном)
      if (order['status'] == 'Очікує оплати') {
        if (!_shownPaymentDialogs.contains(orderId)) {
          _shownPaymentDialogs.add(orderId);
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _showPaymentDialog(order);
          });
        }
      }
    }
  }

  // =========================================================================
  // 🔥 НОВИЙ МЕТОД: ВІКНО "ОПЛАТИТИ" (Замість старого "Узгодження")
  // =========================================================================
  void _showPaymentDialog(Map<String, dynamic> order) {
    final int prepTime = int.tryParse(order['prep_time_minutes'].toString()) ?? 0;
    final String? restaurantComment = order['restaurant_comment'];
    final bool hasComment = restaurantComment != null && restaurantComment.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 50),
              const SizedBox(height: 10),
              Text('Замовлення погоджено!', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ресторан опрацював замовлення і готовий почати готувати.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: textColor)),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer, color: isDark ? Colors.orange[400] : Colors.orange[800]),
                      const SizedBox(width: 8),
                      Text('Час приготування: $prepTime хв', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    ],
                  ),
                ),

                if (hasComment) ...[
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: isDark ? Colors.orange.withOpacity(0.15) : Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange[800]),
                            const SizedBox(width: 8),
                            Text('Коментар від кухні:', style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(restaurantComment, style: TextStyle(color: textColor, fontSize: 14)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Divider(color: isDark ? Colors.white24 : Colors.grey[300]),
                const Text('До сплати:', style: TextStyle(color: Colors.grey, fontSize: 14)),

                // 🔥 ВИПРАВЛЕНО: Обгорнуто в FittedBox для захисту
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            OutlinedButton(
              onPressed: () async {
                Navigator.of(dialogContext, rootNavigator: true).pop(); // Миттєво закриваємо

                // Просте і безпечне скасування (гроші не списувались, тому просто міняємо статус)
                try {
                  await SupabaseService.client.from('orders').update({
                    'status': 'Скасовано',
                    'cancellation_reason': 'Клієнт відмовився від оплати/умов'
                  }).eq('id', order['id'].toString());

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Замовлення скасовано.')));
                } catch (e) {
                  debugPrint('Помилка скасування: $e');
                }
              },
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
              child: const Text('Відмовитись'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext, rootNavigator: true).pop(); // Миттєво закриваємо
                _proceedToPayment(order); // Відкриваємо Монобанк
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('Оплатити'),
            ),
          ],
        );
      },
    );
  }


  // 🔥 МЕТОД ОПЛАТИ (Надійний)
  Future<void> _proceedToPayment(Map<String, dynamic> order) async {
    final String? paymentId = order['payment_id'];
    if (paymentId != null && paymentId.isNotEmpty) {
      final Uri url = Uri.parse('https://pay.mbnk.biz/$paymentId');

      try {
        // ОЦЕЙ РЯДОК РОБИТЬ МАГІЮ З ХРЕСТИКОМ:
        await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
      }

    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рахунок ще не сформовано.'), backgroundColor: Colors.orange));
    }
  }

  void _showReviewDialog(Map<String, dynamic> order) {
    int selectedRating = 0;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 50),
                  const SizedBox(height: 10),
                  Text('Як вам замовлення?', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Замовлення №${order['id'].toString().substring(0, 5)} доставлено.\nОцініть роботу ресторану та кур\'єра:', textAlign: TextAlign.center, style: TextStyle(color: textColor)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        iconSize: 40,
                        padding: EdgeInsets.zero,
                        icon: Icon(index < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded, color: Colors.amber),
                        onPressed: () => setDialogState(() => selectedRating = index + 1),
                      );
                    }),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: commentController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                        hintText: 'Що сподобалось чи не сподобалось?',
                        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12)
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Пізніше', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF005BBB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: (selectedRating == 0 || isSubmitting) ? null : () async {
                    setDialogState(() => isSubmitting = true);
                    final nav = Navigator.of(context);
                    try {
                      await SupabaseService.client.from('orders').update({'rating': selectedRating, 'review_comment': commentController.text.trim()}).eq('id', order['id'].toString());
                      nav.pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дякуємо за ваш відгук! 💛💙'), backgroundColor: Colors.green));
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                    }
                  },
                  child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Відправити'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return Container(
          decoration: BoxDecoration(color: sheetBgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 20),
                    Text('Замовлення №${order['id'].toString().substring(0, 5)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),

                    if (order['status'] == 'Доставлено' && order['rating'] != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: isDark ? Colors.green.withOpacity(0.15) : Colors.green[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green[200]!)),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Ви оцінили на ${order['rating']}/5', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  if (order['review_comment'] != null && order['review_comment'].toString().isNotEmpty)
                                    Text('"${order['review_comment']}"', style: TextStyle(fontStyle: FontStyle.italic, color: textColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (order['status'] == 'Готується' && order['prep_time_minutes'] != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                        child: Row(
                          children: [
                            Icon(Icons.timer, color: isDark ? Colors.orange[400] : Colors.orange[800]),
                            const SizedBox(width: 8),
                            Expanded(
                                child: OrderCountdownTimer(
                                    createdAt: order['created_at'],
                                    prepTimeMinutes: int.tryParse(order['prep_time_minutes'].toString()) ?? 20
                                )
                            ),
                          ],
                        ),
                      ),

                    if (order['status'] == 'Скасовано' && order['cancellation_reason'] != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: isDark ? Colors.red.withOpacity(0.15) : Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red[200]!)),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Причина: ${order['cancellation_reason']}', style: const TextStyle(color: Colors.red))),
                          ],
                        ),
                      ),

                    Divider(height: 30, color: isDark ? Colors.white24 : Colors.grey[300]),

                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: SupabaseService.client.from('order_items').select().eq('order_id', order['id'].toString()),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Порожньо'));

                          final items = snapshot.data!;
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final itemTotal = (item['price'] as num) * (item['quantity'] as num);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${item['dish_name']} x${item['quantity']}', style: TextStyle(color: textColor)),
                                trailing: Text('$itemTotal грн', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Divider(color: isDark ? Colors.white24 : Colors.grey[300]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Разом (з доставкою):', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(width: 8),

                        // 🔥 ВИПРАВЛЕНО: Гнучкий віджет (Flexible), щоб довгий текст не вилазив за екран
                        Flexible(
                          child: Text(
                              '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF005BBB))
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Очікує підтвердження': return Colors.orange;
      case 'Очікує оплати': return Colors.redAccent;
      case 'Готується': return Colors.blue;
      case 'Готово до видачі': return Colors.teal;
      case 'В дорозі': return Colors.deepPurple;
      case 'Доставлено': return Colors.green;
      case 'Скасовано': return Colors.red;
      default: return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emptyStateBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final emptyStateBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final textColor = isDark ? Colors.white : Colors.black87;

    final user = SupabaseService.client.auth.currentUser;

    if (user == null) return const Scaffold(body: Center(child: Text('Будь ласка, авторизуйтесь')));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Мої замовлення', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _orders.isEmpty
              ? Center(
              child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: emptyStateBgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: emptyStateBorder)),
                  child: Text('У вас ще немає замовлень', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))
              )
          )
              : ListView.builder(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 120),
            itemCount: _orders.length,
            itemBuilder: (context, index) {
              final order = _orders[index];
              final date = DateTime.parse(order['created_at']).toLocal();
              final dateString = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
              final statusColor = _getStatusColor(order['status']);

              return _OrderCard(
                order: order,
                dateString: dateString,
                statusColor: statusColor,
                getCourierName: _getCourierName,
                onShowPayment: () => _showPaymentDialog(order),
                onShowDetails: () => _showOrderDetails(context, order),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final String dateString;
  final Color statusColor;
  final Future<String> Function(String?) getCourierName;
  final VoidCallback onShowPayment;
  final VoidCallback onShowDetails;

  const _OrderCard({
    required this.order,
    required this.dateString,
    required this.statusColor,
    required this.getCourierName,
    required this.onShowPayment,
    required this.onShowDetails,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final courierBgColor = isDark ? Colors.deepPurple.withOpacity(0.2) : Colors.deepPurple.withOpacity(0.08);
    final courierTextColor = isDark ? Colors.deepPurple[200]! : Colors.deepPurple;
    final timerBgColor = isDark ? Colors.amber.withOpacity(0.1) : Colors.amber.withOpacity(0.2);

    final order = widget.order;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Замовлення №${order['id'].toString().substring(0, 5)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textColor)),
                    Text(widget.dateString, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),

                // 🔥 ВИПРАВЛЕНО: Повністю безпечний Row для статусу і суми
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: widget.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          order['status'],
                          style: TextStyle(color: widget.statusColor, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                                '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: textColor)
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: isDark ? Colors.white70 : Colors.grey[600]),
                        ],
                      ),
                    ),
                  ],
                ),

                if (_isExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(thickness: 1, color: isDark ? Colors.white24 : Colors.grey[300]),
                  ),

                  if (order['courier_id'] != null && order['status'] != 'Скасовано')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: courierBgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: FutureBuilder<String>(
                            future: widget.getCourierName(order['courier_id']),
                            builder: (context, snapshot) {
                              return Row(
                                children: [
                                  Icon(Icons.delivery_dining, color: courierTextColor, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          'Ваш кур\'єр: ${snapshot.data ?? 'Завантаження...'}',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: courierTextColor)
                                      )
                                  ),
                                ],
                              );
                            }
                        ),
                      ),
                    ),

                  if (order['status'] == 'Очікує оплати')
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: widget.onShowPayment,
                        icon: const Icon(Icons.payment),
                        label: const Text('Оплатити замовлення', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),

                  if (order['status'] == 'Готується' && order['prep_time_minutes'] != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: timerBgColor, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.timer, color: isDark ? Colors.orange[400] : Colors.orange[800], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OrderCountdownTimer(
                                createdAt: order['created_at'],
                                prepTimeMinutes: int.tryParse(order['prep_time_minutes'].toString()) ?? 20
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (order['status'] == 'Скасовано' && order['cancellation_reason'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text('Причина: ${order['cancellation_reason']}', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
                    ),

                  if (order['status'] == 'Готується' || order['status'] == 'В дорозі' || order['status'] == 'Готово до видачі') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ClientOrderTrackingScreen(
                                orderId: order['id'],
                                deliveryAddress: order['delivery_address'] ?? 'Адреса не вказана',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map, size: 20),
                        label: const Text('Відстежити на карті', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: widget.onShowDetails,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF005BBB),
                          side: const BorderSide(color: Color(0xFF005BBB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: const Text('Деталі замовлення', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrderCountdownTimer extends StatefulWidget {
  final String createdAt;
  final int prepTimeMinutes;

  const OrderCountdownTimer({
    super.key,
    required this.createdAt,
    required this.prepTimeMinutes,
  });

  @override
  State<OrderCountdownTimer> createState() => _OrderCountdownTimerState();
}

class _OrderCountdownTimerState extends State<OrderCountdownTimer> {
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
    _targetTime = created.add(Duration(minutes: widget.prepTimeMinutes + 3));
  }

  void _updateTime() {
    final now = DateTime.now();
    final difference = _targetTime.difference(now);

    if (difference.isNegative) {
      if (mounted) {
        setState(() => _timeLeft = 'Ось-ось буде готово!');
      }
      _timer?.cancel();
    } else {
      final minutes = difference.inMinutes.toString().padLeft(2, '0');
      final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
      if (mounted) {
        setState(() => _timeLeft = '$minutes:$seconds');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Text(
      _timeLeft == 'Ось-ось буде готово!'
          ? _timeLeft
          : 'Буде готово через: $_timeLeft',
      style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.orange[400] : Colors.orange[800], fontSize: 15),
    );
  }
}