import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/supabase_service.dart';

class OrderModals {

  // ============================================================================
  // 🔥 1. ВІДХИЛЕННЯ ЗАМОВЛЕННЯ
  // ============================================================================
  static Future<void> cancelOrderWithReason(BuildContext context, dynamic orderId) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Відхилити замовлення?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Будь ласка, вкажіть причину для клієнта:'),
            const SizedBox(height: 12),
            TextField(
                controller: reasonController,
                decoration: InputDecoration(hintText: 'Немає світла, закінчились продукти...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                maxLines: 2
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Повернутися', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обов\'язково вкажіть причину!')));
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Відхилити'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      BuildContext? loaderContext;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          loaderContext = ctx;
          return const PopScope(canPop: false, child: Center(child: CircularProgressIndicator()));
        },
      );

      try {
        await SupabaseService.client.from('orders').update({
          'status': 'Відхилено',
          'cancellation_reason': reasonController.text.trim()
        }).eq('id', orderId.toString());

        if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Замовлення скасовано.'),
              backgroundColor: Colors.orange
          ));
        }
      } catch (e) {
        if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // ============================================================================
  // 🔥 2. ПРИЙНЯТТЯ ЗАМОВЛЕННЯ (Виклик Edge Function для генерації рахунку)
  // ============================================================================
  static void showAcceptOrderDialog(BuildContext context, Map<String, dynamic> order) {
    if (order['desired_delivery_time'] != null) {
      _acceptPreorder(context, order);
      return;
    }

    int selectedTime = 20;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Прийняти замовлення', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Через скільки хвилин страви будуть готові?', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Slider(
                    value: selectedTime.toDouble(), min: 5, max: 120, divisions: 23, activeColor: Colors.green, label: '$selectedTime хв',
                    onChanged: (val) => setDialogState(() => selectedTime = val.toInt()),
                  ),
                  Text('$selectedTime хвилин', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    Navigator.pop(dialogContext); // Закриваємо діалог вибору часу

                    BuildContext? loaderContext;
                    // Показуємо лоадер, зберігаючи його контекст
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) {
                        loaderContext = ctx;
                        return const PopScope(canPop: false, child: Center(child: CircularProgressIndicator()));
                      },
                    );

                    try {
                      // 🔥 Викликаємо нашу нову функцію генерації рахунку
                      await SupabaseService.client.functions.invoke(
                        'mono-create-invoice',
                        body: {
                          'order_id': order['id'].toString(),
                          'prep_time_minutes': selectedTime,
                          'restaurant_comment': order['restaurant_comment'] ?? '',
                        },
                      );

                      if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Рахунок створено! Очікуємо оплату від клієнта.'),
                            backgroundColor: Colors.green
                        ));
                      }
                    } catch (e) {
                      if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
                      if (context.mounted) {
                        // 🔥 ТЕПЕР ТИ ТОЧНО ПОБАЧИШ ПОМИЛКУ СЕРВЕРА
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка сервера: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
                      }
                    }
                  },
                  child: const Text('Підтвердити'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // 🔥 3. ПОПЕРЕДНЄ ЗАМОВЛЕННЯ
  // ============================================================================
  static void _acceptPreorder(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Попереднє замовлення ⏰', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
        content: const Text('Виставити клієнту рахунок на оплату цього замовлення?', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogContext); // Закриваємо діалог

              BuildContext? loaderContext;
              showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) {
                    loaderContext = ctx;
                    return const PopScope(canPop: false, child: Center(child: CircularProgressIndicator()));
                  }
              );

              try {
                // Виставляємо рахунок через нову функцію
                await SupabaseService.client.functions.invoke(
                  'mono-create-invoice',
                  body: {
                    'order_id': order['id'].toString(),
                    'prep_time_minutes': 0, // Час прив'язаний до desired_delivery_time
                    'restaurant_comment': 'Попереднє замовлення. ' + (order['restaurant_comment'] ?? ''),
                  },
                );

                if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рахунок виставлено! Чекаємо оплату.'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Виставити рахунок'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // 🔥 4. ВИДАЛЕННЯ СТРАВИ З ЧЕКА
  // ============================================================================
  static Future<void> _confirmRemoveItem(BuildContext context, Map<String, dynamic> item, Map<String, dynamic> order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Видалити страву?'),
        content: Text('Видалити "${item['dish_name']}" із замовлення?\n\nСуму буде автоматично перераховано.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Видалити', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    BuildContext? loaderContext;
    try {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            loaderContext = ctx;
            return const PopScope(canPop: false, child: Center(child: CircularProgressIndicator()));
          }
      );

      await SupabaseService.client.from('order_items').delete().eq('id', item['id'].toString());

      final itemTotal = (item['price'] as num) * (item['quantity'] as num);
      final newTotalAmount = (order['total_amount'] as num) - itemTotal;

      String existingComment = order['restaurant_comment'] ?? '';
      String autoWarning = 'Увага! Страва "${item['dish_name']}" була відсутня та видалена з чека. Суму перераховано.';
      String newComment = existingComment.contains(autoWarning) ? existingComment : '$autoWarning $existingComment'.trim();

      await SupabaseService.client.from('orders').update({
        'total_amount': newTotalAmount,
        'restaurant_comment': newComment
      }).eq('id', order['id'].toString());

      if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
      if (context.mounted) {
        Navigator.pop(context); // Закриваємо модалку деталей, щоб оновити список
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['dish_name']} видалено! Суму змінено.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (loaderContext != null && loaderContext!.mounted) Navigator.pop(loaderContext!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ============================================================================
  // 🔥 5. ДЕТАЛІ ЗАМОВЛЕННЯ
  // ============================================================================
  static void showOrderDetails(BuildContext context, Map<String, dynamic> order, dynamic restaurantId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  Text('Замовлення №${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const Divider(),

                  if (order['restaurant_comment'] != null && order['restaurant_comment'].toString().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange[200]!)),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.deepOrange),
                          const SizedBox(width: 8),
                          Expanded(child: Text(order['restaurant_comment'], style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),

                  const Text('Склад замовлення:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: SupabaseService.client.from('order_items').select().eq('order_id', order['id'].toString()),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        final items = snapshot.data ?? [];
                        if (items.isEmpty) return const Center(child: Text('Порожньо'));
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final itemTotal = (item['price'] as num) * (item['quantity'] as num);

                            List<String> removed = [];
                            if (item['removed_ingredients'] != null) {
                              try {
                                var raw = item['removed_ingredients'];
                                var decoded = raw is String ? jsonDecode(raw) : raw;
                                removed = List<String>.from((decoded as List).map((e) => e.toString()));
                              } catch (_) {}
                            }

                            List<dynamic> added = [];
                            if (item['added_ingredients'] != null) {
                              try {
                                var raw = item['added_ingredients'];
                                var decoded = raw is String ? jsonDecode(raw) : raw;
                                added = List<dynamic>.from(decoded as List);
                              } catch (_) {}
                            }

                            final bool hasMods = removed.isNotEmpty || added.isNotEmpty;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              title: Text('${item['dish_name']} x${item['quantity']}', style: const TextStyle(fontWeight: FontWeight.bold)),

                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item['price']} грн/шт'),
                                  if (hasMods)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (removed.isNotEmpty)
                                            ...removed.map((i) => Text('- Без: $i', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold))),
                                          if (added.isNotEmpty)
                                            ...added.map((i) => Text('+ Дод: ${i['name'] ?? ''}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$itemTotal грн', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(width: 8),
                                  if (order['status'] == 'Очікує підтвердження')
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _confirmRemoveItem(context, item, order),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Разом:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      // 🔥 ВИПРАВЛЕНО: Обрізано копійки і додано захист від переповнення екрана
                      Flexible(
                        child: Text(
                            '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red[800])
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}