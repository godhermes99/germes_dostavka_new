import 'package:flutter/material.dart';
import '../core/supabase_service.dart';

// ============================================================================
// СТАТИСТИКА РЕСТОРАНУ ДЛЯ МЕНЕДЖЕРА
// ============================================================================
class RestaurantStatisticsView extends StatefulWidget {
  final dynamic restaurantId;
  const RestaurantStatisticsView({super.key, required this.restaurantId});

  @override
  State<RestaurantStatisticsView> createState() => _RestaurantStatisticsViewState();
}

class _RestaurantStatisticsViewState extends State<RestaurantStatisticsView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTimeRange? _selectedDateRange;
  int _selectedDays = 1;

  @override
  void initState() {
    super.initState();
    _setQuickFilter(1);
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
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: Colors.red[800]!),
          ),
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

  // Функція для отримання товарів за списком ID замовлень
  Future<List<Map<String, dynamic>>> _fetchOrderItemsForOrders(List<String> orderIds) async {
    if (orderIds.isEmpty) return [];

    try {
      final response = await SupabaseService.client
          .from('order_items')
          .select()
          .filter('order_id', 'in', orderIds);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Помилка завантаження товарів для статистики: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('restaurant_id', widget.restaurantId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final allOrders = snapshot.data ?? [];

        final startUtc = _selectedDateRange!.start.toUtc();
        final endUtc = _selectedDateRange!.end.add(const Duration(hours: 23, minutes: 59, seconds: 59)).toUtc();

        final periodOrders = allOrders.where((o) {
          final createdAt = DateTime.parse(o['created_at']).toUtc();
          return createdAt.isAfter(startUtc) && createdAt.isBefore(endUtc);
        }).toList();

        final deliveredOrders = periodOrders.where((o) => o['status'] == 'Доставлено').toList();
        final deliveredOrderIds = deliveredOrders.map((o) => o['id'].toString()).toList();

        final canceled = periodOrders.where((o) => o['status'] == 'Скасовано');

        final ratedOrders = periodOrders.where((o) => o['rating'] != null);
        final averageRating = ratedOrders.isEmpty
            ? 0.0
            : ratedOrders.fold(0.0, (sum, o) => sum + (o['rating'] as num)) / ratedOrders.length;

        // Завантажуємо order_items ТІЛЬКИ для доставлених замовлень, щоб порахувати чисту виручку
        return FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchOrderItemsForOrders(deliveredOrderIds),
            builder: (context, itemsSnapshot) {

              // Рахуємо чисту виручку (без доставки)
              double cleanRevenue = 0.0;
              if (itemsSnapshot.hasData && itemsSnapshot.data!.isNotEmpty) {
                final items = itemsSnapshot.data!;
                cleanRevenue = items.fold(0.0, (sum, item) {
                  final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                  final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                  return sum + (price * quantity);
                });
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    const Text('Показники', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Сьогодні', style: TextStyle(fontWeight: FontWeight.bold)),
                            selected: _selectedDays == 1,
                            selectedColor: Colors.red[100],
                            onSelected: (_) => _setQuickFilter(1),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('7 днів', style: TextStyle(fontWeight: FontWeight.bold)),
                            selected: _selectedDays == 7,
                            selectedColor: Colors.red[100],
                            onSelected: (_) => _setQuickFilter(7),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('30 днів', style: TextStyle(fontWeight: FontWeight.bold)),
                            selected: _selectedDays == 30,
                            selectedColor: Colors.red[100],
                            onSelected: (_) => _setQuickFilter(30),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            label: const Text('Календар'),
                            avatar: const Icon(Icons.calendar_month, size: 18),
                            backgroundColor: _selectedDays == 0 ? Colors.red[100] : Colors.grey[200],
                            onPressed: _pickDateRange,
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Text(
                        _selectedDateRange!.start == _selectedDateRange!.end
                            ? 'Період: ${_formatDate(_selectedDateRange!.start)}'
                            : 'Період: ${_formatDate(_selectedDateRange!.start)} - ${_formatDate(_selectedDateRange!.end)}',
                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ),

                    Row(
                      children: [
                        // ТУТ ВИВОДИМО ЧИСТУ ВИРУЧКУ
                        _buildStatCard('Виручка', '${cleanRevenue.toStringAsFixed(0)} грн', Icons.account_balance_wallet, Colors.green),
                        const SizedBox(width: 12),
                        _buildStatCard('Виконано', '${deliveredOrders.length} шт', Icons.check_circle, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStatCard('Скасовано', '${canceled.length} шт', Icons.cancel, Colors.red),
                        const SizedBox(width: 12),
                        _buildStatCard('Рейтинг', ratedOrders.isEmpty ? 'Немає' : averageRating.toStringAsFixed(1), Icons.star, Colors.amber),
                      ],
                    ),

                    const SizedBox(height: 30),
                    const Text('Відгуки за цей період', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    if (ratedOrders.isEmpty)
                      const Text('За вибраний період відгуків немає', style: TextStyle(color: Colors.grey)),

                    ...ratedOrders.take(10).map((o) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.star, color: Colors.white)),
                          title: Text('${o['rating']} / 5', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(o['review_comment']?.toString().isNotEmpty == true ? o['review_comment'] : 'Без коментаря'),
                          trailing: Text(DateTime.parse(o['created_at']).toLocal().toString().substring(5, 10)),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}