import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../core/supabase_service.dart';
import 'checkout_screen.dart';

// ==================== КОШИК ====================
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // =========================================================
    // 🔥 МАГІЧНИЙ БЛОК ДЛЯ АДАПТАЦІЇ ТЕМИ
    // =========================================================
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final bottomPanelColor = isDark ? Colors.black.withOpacity(0.85) : Colors.white.withOpacity(0.95);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final iconBgColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100]!;
    // =========================================================

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Кошик', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
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
          // ЦЕЙ ФІЛЬТР ЗАВЖДИ ЧОРНИЙ
          color: Colors.black.withOpacity(0.4),
          child: Consumer<CartProvider>(
            builder: (context, cart, child) {

              // --- ЕКРАН ПОРОЖНЬОГО КОШИКА ---
              if (cart.items.isEmpty) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: cardColor, // 🔥 Адаптивний колір
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor, width: 1.5), // 🔥 Адаптивна рамка
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle), // 🔥 Адаптивний фон іконки
                          child: const Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        Text('Кошик порожній', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)), // 🔥 Адаптивний текст
                        const SizedBox(height: 8),
                        Text('Додайте щось смачненьке! 😊', style: TextStyle(fontSize: 16, color: subtitleColor)), // 🔥 Адаптивний текст
                      ],
                    ),
                  ),
                );
              }

              // --- ЕКРАН ЗАПОВНЕНОГО КОШИКА ---
              final bool hasWeightItems = cart.items.any((item) => item['is_by_weight'] == true);

              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 16, bottom: 20),
                      itemCount: cart.items.length,
                      itemBuilder: (context, index) {
                        final item = cart.items[index];
                        final bool isByWeight = item['is_by_weight'] ?? false;
                        final String weightMeasure = item['weight_measure'] ?? '100 г';
                        final String priceText = isByWeight ? '${item['price']} грн / $weightMeasure' : '${item['price']} грн';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                          decoration: BoxDecoration(
                            color: cardColor, // 🔥 Адаптивна картка товару
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor, width: 1.5),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                      item['image_url'] ?? item['image'] ?? '',
                                      width: 75, height: 75, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(width: 75, height: 75, color: iconBgColor)
                                  ),
                                ),
                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)), // 🔥 Адаптивний текст

                                      if (item['removed_ingredients'] != null && (item['removed_ingredients'] as List).isNotEmpty)
                                        ...((item['removed_ingredients'] as List).map((i) => Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text('- Без: $i', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ))),

                                      if (item['added_ingredients'] != null && (item['added_ingredients'] as List).isNotEmpty)
                                        ...((item['added_ingredients'] as List).map((i) => Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text('+ Додано: ${i['name']}', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ))),

                                      const SizedBox(height: 8),

                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        children: [
                                          Text(priceText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF005BBB))),
                                          if (isByWeight)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple[200]!)),
                                              child: const Text('Вагова', style: TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // КНОПКИ ПЛЮС ТА МІНУС
                                Container(
                                  decoration: BoxDecoration(
                                    color: iconBgColor, // 🔥 Адаптивний фон кнопок
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(Icons.add, size: 20, color: textColor), // 🔥 Адаптивний колір іконки
                                        onPressed: () {
                                          item['quantity'] = item['quantity'] + 1;
                                          cart.notifyListeners();
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Text('${item['quantity']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)), // 🔥 Адаптивний текст
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(item['quantity'] > 1 ? Icons.remove : Icons.delete_outline, size: 20, color: item['quantity'] > 1 ? textColor : Colors.red), // 🔥 Адаптивний колір іконки
                                        onPressed: () {
                                          if (item['quantity'] > 1) {
                                            item['quantity'] = item['quantity'] - 1;
                                            cart.notifyListeners();
                                          } else {
                                            cart.removeItem(item['cart_key']?.toString() ?? item['id'].toString());
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // --- ПІДСУМОК (НИЖНЯ ПАНЕЛЬ) ---
                  FutureBuilder<Map<String, dynamic>?>(
                      future: SupabaseService.client.from('settings').select('base_price').eq('id', 1).maybeSingle(),
                      builder: (context, snapshot) {
                        final double basePrice = (snapshot.data?['base_price'] as num?)?.toDouble() ?? 40.0;
                        final double totalWithDeliveryEstimate = cart.total + basePrice;

                        return Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                          decoration: BoxDecoration(
                            color: bottomPanelColor, // 🔥 Адаптивна нижня панель
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, -5))],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasWeightItems)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.1), // 🔥 Адаптивний банер для вагових страв
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.purple.withOpacity(0.3))
                                  ),
                                  child: const Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.balance, color: Colors.purpleAccent, size: 20), // Трохи яскравіше для обох тем
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'У кошику є вагові страви. Кінцева вартість може змінитися після зважування в ресторані.',
                                          style: TextStyle(color: Colors.purpleAccent, fontSize: 13, fontWeight: FontWeight.w600), // Трохи яскравіше
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Сума товарів:', style: TextStyle(fontSize: 16, color: subtitleColor, fontWeight: FontWeight.w600)), // 🔥 Адаптивний текст
                                  Text('${cart.total.toStringAsFixed(0)} грн', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)), // 🔥 Адаптивний текст
                                ],
                              ),
                              const SizedBox(height: 8),

                              // --- ДИНАМІЧНА ДОСТАВКА ---
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Доставка:', style: TextStyle(fontSize: 16, color: subtitleColor, fontWeight: FontWeight.w600)), // 🔥 Адаптивний текст
                                  snapshot.connectionState == ConnectionState.waiting
                                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Text('від ${basePrice.toStringAsFixed(0)} грн', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)), // 🔥 Адаптивний текст
                                ],
                              ),

                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey[300]), // 🔥 Адаптивний розділювач
                              ),

                              // --- ДИНАМІЧНИЙ ПІДСУМОК ---
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Разом', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor)), // 🔥 Адаптивний текст
                                  snapshot.connectionState == ConnectionState.waiting
                                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Text('${totalWithDeliveryEstimate.toStringAsFixed(0)} грн', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF005BBB))),
                                ],
                              ),

                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFCD00),
                                      elevation: 4,
                                      shadowColor: Colors.black45,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                  ),
                                  onPressed: () {
                                    if (cart.items.isEmpty) return;

                                    if (cart.restaurantId == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Помилка: неможливо визначити ресторан')));
                                      return;
                                    }

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CheckoutScreen(
                                          restaurantId: cart.restaurantId!,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Перейти до оформлення', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}