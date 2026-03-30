<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/supabase_service.dart';
import 'order_modals.dart';

class OrdersListTab extends StatefulWidget {
  final String statusFilter;
  final dynamic restaurantId;
  final List<Map<String, dynamic>> orders; // 🔥 ТЕПЕР ПРИЙМАЄМО ДАНІ ВІД ГОЛОВНОГО ЕКРАНА

  const OrdersListTab({super.key, required this.statusFilter, required this.restaurantId, required this.orders});

  @override
  State<OrdersListTab> createState() => _OrdersListTabState();
}

class _OrdersListTabState extends State<OrdersListTab> {

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Очікує підтвердження': return Colors.redAccent;
      case 'Очікує оплати': return Colors.orange;
      case 'Готується': return Colors.blue;
      case 'Готово до видачі': return Colors.teal;
      case 'В дорозі': return Colors.deepPurple;
      case 'Доставлено': return Colors.green;
      case 'Скасовано':
      case 'Відхилено': return Colors.grey;
      default: return Colors.black;
    }
  }

  Future<void> _updateOrderStatus(BuildContext context, dynamic orderId, String newStatus) async {
    try {
      await SupabaseService.client.from('orders').update({'status': newStatus}).eq('id', orderId.toString());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Статус: $newStatus'), backgroundColor: Colors.green));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<String> _getCourierName(String? courierId) async {
    if (courierId == null || courierId.isEmpty) return 'Не призначено';
    try {
      final profile = await SupabaseService.client.from('profiles').select('full_name').eq('user_id', courierId).maybeSingle();
      return profile?['full_name'] ?? 'Невідомий кур\'єр';
    } catch (e) {
      return 'Помилка завантаження';
    }
  }

  Widget _buildOrderItemsPreview(dynamic itemsData) {
    List<dynamic> items = [];
    if (itemsData is String) {
      try { items = jsonDecode(itemsData); } catch (_) {}
    } else if (itemsData is List) {
      items = itemsData;
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map<Widget>((item) {
          final int quantity = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final String name = item['name']?.toString() ?? 'Невідома страва';

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

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${quantity}x $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (hasMods)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (removed.isNotEmpty) ...removed.map((i) => Text('- Без: $i', style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold))),
                        if (added.isNotEmpty) ...added.map((i) => Text('+ Дод: ${i['name'] ?? ''}', style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('У цій категорії немає замовлень', style: TextStyle(fontSize: 16, color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final date = DateTime.parse(order['created_at']).toLocal();
        final timeString = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

        final bool isPreorder = order['desired_delivery_time'] != null;
        String preorderTimeStr = '';
        if (isPreorder) {
          final dt = DateTime.parse(order['desired_delivery_time']).toLocal();
          preorderTimeStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} о ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        final String status = order['status'];

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: _getStatusColor(status), width: status == 'Очікує підтвердження' ? 2 : 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPreorder)
                Container(
                  width: double.infinity,
                  color: Colors.purple[100],
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(children: [
                    const Icon(Icons.alarm, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(child: Text('ПОПЕРЕДНЄ НА $preorderTimeStr', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 15)))
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('№ ${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            status,
                            style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),

                    if (order['prep_time_minutes'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(children: [
                            const Icon(Icons.timer, color: Colors.orange, size: 16),
                            const SizedBox(width: 4),
                            Text('Час: ${order['prep_time_minutes']} хв', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                          ])
                      ),

                    if (status == 'Скасовано' || status == 'Відхилено')
                      if (order['cancellation_reason'] != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.cancel, color: Colors.red, size: 16),
                                const SizedBox(width: 4),
                                Expanded(child: Text('Причина: ${order['cancellation_reason']}', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))),
                              ],
                            )
                        ),

                    if (order['courier_id'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.withOpacity(0.3))),
                          child: FutureBuilder<String>(
                              future: _getCourierName(order['courier_id']),
                              builder: (context, snapshot) {
                                return Row(
                                  children: [
                                    const Icon(Icons.delivery_dining, color: Colors.deepPurple, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Кур\'єр: ${snapshot.data ?? 'Завантаження...'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple))),
                                  ],
                                );
                              }
                          ),
                        ),
                      ),

                    _buildOrderItemsPreview(order['items']),

                    const Divider(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 8.0,
                        runSpacing: 8.0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton(
                              onPressed: () => OrderModals.showOrderDetails(context, order, widget.restaurantId),
                              child: const Text('Повний чек')
                          ),

                          if (status == 'Очікує підтвердження') ...[
                            IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                tooltip: 'Відхилити',
                                onPressed: () => OrderModals.cancelOrderWithReason(context, order['id'])
                            ),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => OrderModals.showAcceptOrderDialog(context, order),
                                child: const Text('Прийняти')
                            ),
                          ],

                          if (status == 'Очікує оплати')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hourglass_empty, color: Colors.orange, size: 16),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text('Чекаємо оплату від клієнта', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))),
                                ],
                              ),
                            ),

                          if (status == 'Готується')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                              icon: const Icon(Icons.room_service, size: 18),
                              label: const Text('Готово!'),
                              onPressed: () => _updateOrderStatus(context, order['id'], 'Готово до видачі'),
                            ),

                          if (status == 'Готово до видачі')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                              icon: const Icon(Icons.delivery_dining, size: 18),
                              label: const Text('Відправити'),
                              onPressed: () => _updateOrderStatus(context, order['id'], 'В дорозі'),
                            ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredOrders = [];

    // 🔥 ФІЛЬТРУЄМО ТЕ, ЩО ОТРИМАЛИ ВІД БАТЬКА
    if (widget.statusFilter == 'Очікує підтвердження') {
      filteredOrders = widget.orders.where((o) =>
      o['status'] == 'Очікує підтвердження' || o['status'] == 'Очікує оплати').toList();
    } else if (widget.statusFilter == 'В роботі') {
      filteredOrders = widget.orders.where((o) =>
      o['status'] == 'Готується' || o['status'] == 'Готово до видачі' || o['status'] == 'В дорозі').toList();
    } else if (widget.statusFilter == 'Історія') {
      filteredOrders = widget.orders.where((o) =>
      o['status'] == 'Доставлено' || o['status'] == 'Скасовано' || o['status'] == 'Відхилено').toList();
    }

    return _buildOrderList(context, filteredOrders);
  }
=======
import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/supabase_service.dart';
import 'order_modals.dart';

class OrdersListTab extends StatefulWidget {
  final String statusFilter;
  final dynamic restaurantId;

  const OrdersListTab({super.key, required this.statusFilter, required this.restaurantId});

  @override
  State<OrdersListTab> createState() => _OrdersListTabState();
}

class _OrdersListTabState extends State<OrdersListTab> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late Stream<List<Map<String, dynamic>>> _ordersStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStream();
  }

  void _initStream() {
    _ordersStream = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', widget.restaurantId)
        .order('created_at', ascending: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _initStream();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Очікує підтвердження': return Colors.redAccent;
      case 'Очікує оплати': return Colors.orange;
      case 'Готується': return Colors.blue;
      case 'Готово до видачі': return Colors.teal;
      case 'В дорозі': return Colors.deepPurple;
      case 'Доставлено': return Colors.green;
      case 'Скасовано':
      case 'Відхилено': return Colors.grey;
      default: return Colors.black;
    }
  }

  Future<void> _updateOrderStatus(BuildContext context, dynamic orderId, String newStatus) async {
    try {
      await SupabaseService.client.from('orders').update({'status': newStatus}).eq('id', orderId.toString());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Статус: $newStatus'), backgroundColor: Colors.green));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
    }
  }

  Future<String> _getCourierName(String? courierId) async {
    if (courierId == null || courierId.isEmpty) return 'Не призначено';
    try {
      final profile = await SupabaseService.client.from('profiles').select('full_name').eq('user_id', courierId).maybeSingle();
      return profile?['full_name'] ?? 'Невідомий кур\'єр';
    } catch (e) {
      return 'Помилка завантаження';
    }
  }

  Widget _buildOrderItemsPreview(dynamic itemsData) {
    List<dynamic> items = [];
    if (itemsData is String) {
      try { items = jsonDecode(itemsData); } catch (_) {}
    } else if (itemsData is List) {
      items = itemsData;
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map<Widget>((item) {
          final int quantity = int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final String name = item['name']?.toString() ?? 'Невідома страва';

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

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${quantity}x $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (hasMods)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (removed.isNotEmpty) ...removed.map((i) => Text('- Без: $i', style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold))),
                        if (added.isNotEmpty) ...added.map((i) => Text('+ Дод: ${i['name'] ?? ''}', style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('У цій категорії немає замовлень', style: TextStyle(fontSize: 16, color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final date = DateTime.parse(order['created_at']).toLocal();
        final timeString = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

        final bool isPreorder = order['desired_delivery_time'] != null;
        String preorderTimeStr = '';
        if (isPreorder) {
          final dt = DateTime.parse(order['desired_delivery_time']).toLocal();
          preorderTimeStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} о ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        final String status = order['status'];

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: _getStatusColor(status), width: status == 'Очікує підтвердження' ? 2 : 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPreorder)
                Container(
                  width: double.infinity,
                  color: Colors.purple[100],
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(children: [
                    const Icon(Icons.alarm, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(child: Text('ПОПЕРЕДНЄ НА $preorderTimeStr', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 15)))
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('№ ${order['id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            status,
                            style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${(order['total_amount'] as num).toStringAsFixed(2)} грн',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),

                    if (order['prep_time_minutes'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(children: [
                            const Icon(Icons.timer, color: Colors.orange, size: 16),
                            const SizedBox(width: 4),
                            Text('Час: ${order['prep_time_minutes']} хв', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                          ])
                      ),

                    // 🔥 БРОНЕБІЙНИЙ ЗАХИСТ: Причина скасування (тепер не викличе зебру)
                    if (status == 'Скасовано' || status == 'Відхилено')
                      if (order['cancellation_reason'] != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.cancel, color: Colors.red, size: 16),
                                const SizedBox(width: 4),
                                Expanded(child: Text('Причина: ${order['cancellation_reason']}', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))),
                              ],
                            )
                        ),

                    if (order['courier_id'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.withOpacity(0.3))),
                          child: FutureBuilder<String>(
                              future: _getCourierName(order['courier_id']),
                              builder: (context, snapshot) {
                                return Row(
                                  children: [
                                    const Icon(Icons.delivery_dining, color: Colors.deepPurple, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Кур\'єр: ${snapshot.data ?? 'Завантаження...'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple))),
                                  ],
                                );
                              }
                          ),
                        ),
                      ),

                    _buildOrderItemsPreview(order['items']),

                    const Divider(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: 8.0,
                        runSpacing: 8.0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton(
                              onPressed: () => OrderModals.showOrderDetails(context, order, widget.restaurantId),
                              child: const Text('Повний чек')
                          ),

                          if (status == 'Очікує підтвердження') ...[
                            IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                tooltip: 'Відхилити',
                                onPressed: () => OrderModals.cancelOrderWithReason(context, order['id'])
                            ),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => OrderModals.showAcceptOrderDialog(context, order),
                                child: const Text('Прийняти')
                            ),
                          ],

                          if (status == 'Очікує оплати')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hourglass_empty, color: Colors.orange, size: 16),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text('Чекаємо оплату від клієнта', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))),
                                ],
                              ),
                            ),

                          if (status == 'Готується')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                              icon: const Icon(Icons.room_service, size: 18),
                              label: const Text('Готово!'),
                              onPressed: () => _updateOrderStatus(context, order['id'], 'Готово до видачі'),
                            ),

                          if (status == 'Готово до видачі')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                              icon: const Icon(Icons.delivery_dining, size: 18),
                              label: const Text('Відправити'),
                              onPressed: () => _updateOrderStatus(context, order['id'], 'В дорозі'),
                            ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data ?? [];
        List<Map<String, dynamic>> filteredOrders = [];

        if (widget.statusFilter == 'Очікує підтвердження') {
          filteredOrders = orders.where((o) =>
          o['status'] == 'Очікує підтвердження' ||
              o['status'] == 'Очікує оплати').toList();
        } else if (widget.statusFilter == 'В роботі') {
          filteredOrders = orders.where((o) =>
          o['status'] == 'Готується' ||
              o['status'] == 'Готово до видачі' ||
              o['status'] == 'В дорозі').toList();
        } else if (widget.statusFilter == 'Історія') {
          filteredOrders = orders.where((o) =>
          o['status'] == 'Доставлено' ||
              o['status'] == 'Скасовано' ||
              o['status'] == 'Відхилено').toList();
        }

        return _buildOrderList(context, filteredOrders);
      },
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}