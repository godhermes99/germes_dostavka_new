import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/supabase_service.dart';
import '../providers/cart_provider.dart';
import '../utils/restaurant_helper.dart';
import 'cart_screen.dart';

class RestaurantMenuScreen extends StatefulWidget {
  final Map<String, dynamic> restaurant;
  final Map<String, dynamic>? initialDish;
  final String? initialCategory;
  final Map<String, String>? categoryEmojis;

  const RestaurantMenuScreen({
    super.key,
    required this.restaurant,
    this.initialDish,
    this.initialCategory,
    this.categoryEmojis,
  });

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen>
    with WidgetsBindingObserver {
  String? _selectedCategory;
  bool _hasOpenedInitialDish = false;
  late Stream<List<Map<String, dynamic>>> _dishesStream;
  List<dynamic> _favoriteDishIds = [];

  late Map<String, dynamic> _currentRestaurant;
  StreamSubscription? _restaurantSub;

  @override
  void initState() {
    super.initState();
    _currentRestaurant = widget.restaurant;
    WidgetsBinding.instance.addObserver(this);

    if (widget.initialCategory != null && widget.initialCategory != 'Всі') {
      _selectedCategory = widget.initialCategory;
    }

    _restaurantSub = SupabaseService.client
        .from('restaurants')
        .stream(primaryKey: ['id'])
        .eq('id', _currentRestaurant['id'])
        .listen((data) {
      if (data.isNotEmpty && mounted) setState(() =>
      _currentRestaurant = data.first);
    });

    _dishesStream = SupabaseService.client
        .from('dishes')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', _currentRestaurant['id'])
        .order('name');
    _loadFavorites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restaurantSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRestaurantData();
  }

  Future<void> _refreshRestaurantData() async {
    try {
      final res = await SupabaseService.client.from('restaurants').select().eq(
          'id', _currentRestaurant['id']).single();
      if (mounted) setState(() => _currentRestaurant = res);
    } catch (e) {
      debugPrint('Помилка: $e');
    }
  }

  Future<void> _loadFavorites() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await SupabaseService.client.from('favorites').select(
          'dish_id').eq('user_id', user.id);
      if (mounted) setState(() =>
      _favoriteDishIds = res.map((f) => f['dish_id']).toList());
    } catch (e) {
      debugPrint('Помилка завантаження: $e');
    }
  }

  Future<void> _toggleFavorite(dynamic dishId) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Увійдіть, щоб зберігати страви')));
      return;
    }
    final isFav = _favoriteDishIds.contains(dishId);
    setState(() {
      if (isFav)
        _favoriteDishIds.remove(dishId);
      else
        _favoriteDishIds.add(dishId);
    });
    try {
      if (isFav) {
        await SupabaseService.client.from('favorites').delete().eq(
            'user_id', user.id).eq('dish_id', dishId);
      } else {
        await SupabaseService.client.from('favorites').insert(
            {'user_id': user.id, 'dish_id': dishId});
      }
    } catch (e) {
      setState(() {
        if (isFav)
          _favoriteDishIds.add(dishId);
        else
          _favoriteDishIds.remove(dishId);
      });
    }
  }

  void _showClearCartDialog(BuildContext context, CartProvider cart,
      Map<String, dynamic> dish) {
    // Адаптація для діалогу (через Theme.of)
    showDialog(
      context: context,
      builder: (_) =>
          AlertDialog(
            title: const Text('Зміна закладу'),
            content: const Text(
                'У вашому кошику вже є страви з іншого ресторану. Очистити кошик, щоб додати цю страву?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text(
                      'Скасувати', style: TextStyle(color: Colors.grey))),
              TextButton(
                  onPressed: () {
                    cart.clear();
                    cart.addItem(dish);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Кошик очищено. ${dish['name']} додано!')));
                  },
                  child: const Text(
                      'Очистити кошик', style: TextStyle(color: Colors.red))
              ),
            ],
          ),
    );
  }

  void _showDishDetails(BuildContext context, Map<String, dynamic> originalDish, bool isOpen) {
    final Map<String, dynamic> dish = Map<String, dynamic>.from(originalDish);

    List<String> removedIngredients = [];
    List<Map<String, dynamic>> addedIngredients = [];

    bool isRemoveExpanded = false;
    bool isAddExpanded = false;

    // 🔥 АДАПТАЦІЯ ТЕМИ ДЛЯ ДЕТАЛЕЙ СТРАВИ (BOTTOM SHEET)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.grey[800];
    final accordionBgColor = isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50];
    final accordionBorderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setModalState) {
              final isFav = _favoriteDishIds.contains(dish['id']);
              final bool isByWeight = dish['is_by_weight'] ?? false;
              final String weightMeasure = dish['weight_measure'] ?? '100 г';

              double basePrice = double.tryParse(dish['price'].toString()) ?? 0.0;
              double additionalPrice = addedIngredients.fold(0.0, (sum, item) => sum + (double.tryParse(item['price'].toString()) ?? 0.0));
              double finalPrice = basePrice + additionalPrice;
              final String priceText = isByWeight ? '${finalPrice.toStringAsFixed(0)} грн / $weightMeasure' : '${finalPrice.toStringAsFixed(0)} грн';

              List<String> removableList = List<String>.from(dish['removable_ingredients'] ?? []);
              List<Map<String, dynamic>> addableList = List<Map<String, dynamic>>.from(dish['addable_ingredients'] ?? []);

              return Container(
                decoration: BoxDecoration(color: sheetBgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: DraggableScrollableSheet(
                  initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
                  builder: (_, scrollController) => Column(
                    children: [
                      // --- ПОВЗУНОК ---
                      Container(width: 40, height: 5, margin: const EdgeInsets.only(top: 12, bottom: 12), decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(10))),

                      // --- СКРОЛ-КОНТЕНТ ---
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(dish['image_url'] ?? dish['image'] ?? '', width: double.infinity, height: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 220, color: accordionBgColor))
                              ),
                              const SizedBox(height: 16),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: Text(dish['name'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2, color: textColor))),
                                  GestureDetector(onTap: () { _toggleFavorite(dish['id']); setModalState(() {}); }, child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : Colors.grey[400], size: 28)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(priceText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF005BBB))),
                              const SizedBox(height: 12),
                              Text(dish['description'] ?? 'Опис відсутній', style: TextStyle(fontSize: 15, height: 1.4, color: subtitleColor)),

                              if (removableList.isNotEmpty || addableList.isNotEmpty) const SizedBox(height: 24),

                              // ==============================================================
                              // БЛОК "ПРИБРАТИ ІНГРЕДІЄНТИ" (АКОРДЕОН)
                              // ==============================================================
                              if (removableList.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                      color: accordionBgColor,
                                      border: Border.all(color: accordionBorderColor),
                                      borderRadius: BorderRadius.circular(16)
                                  ),
                                  child: Column(
                                    children: [
                                      InkWell(
                                        onTap: () => setModalState(() => isRemoveExpanded = !isRemoveExpanded),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                                  const SizedBox(width: 8),
                                                  Text('Прибрати інгредієнти', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                                                ],
                                              ),
                                              Icon(isRemoveExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey[500]),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Якщо натиснули - показуємо список
                                      if (isRemoveExpanded)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                          child: Column(
                                            children: removableList.map((ingredient) {
                                              final isRemoved = removedIngredients.contains(ingredient);
                                              return CheckboxListTile(
                                                title: Text(ingredient, style: TextStyle(decoration: isRemoved ? TextDecoration.lineThrough : null, color: isRemoved ? Colors.grey : textColor, fontSize: 15)),
                                                value: !isRemoved,
                                                activeColor: const Color(0xFF005BBB),
                                                controlAffinity: ListTileControlAffinity.leading,
                                                contentPadding: EdgeInsets.zero,
                                                visualDensity: VisualDensity.compact,
                                                onChanged: (bool? checked) {
                                                  setModalState(() {
                                                    if (checked == true) removedIngredients.remove(ingredient);
                                                    else removedIngredients.add(ingredient);
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        )
                                    ],
                                  ),
                                ),

                              // ==============================================================
                              // БЛОК "ДОДАТИ ДО СТРАВИ" (АКОРДЕОН)
                              // ==============================================================
                              if (addableList.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                      color: accordionBgColor,
                                      border: Border.all(color: accordionBorderColor),
                                      borderRadius: BorderRadius.circular(16)
                                  ),
                                  child: Column(
                                    children: [
                                      InkWell(
                                        onTap: () => setModalState(() => isAddExpanded = !isAddExpanded),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                                                  const SizedBox(width: 8),
                                                  Text('Додати до страви', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                                                ],
                                              ),
                                              Icon(isAddExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey[500]),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Якщо натиснули - показуємо список
                                      if (isAddExpanded)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                          child: Column(
                                            children: addableList.map((ingredient) {
                                              final isAdded = addedIngredients.any((item) => item['name'] == ingredient['name']);
                                              return CheckboxListTile(
                                                title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(ingredient['name'], style: TextStyle(fontSize: 15, color: textColor)), Text('+${ingredient['price']} грн', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))]),
                                                value: isAdded,
                                                activeColor: Colors.green,
                                                controlAffinity: ListTileControlAffinity.leading,
                                                contentPadding: EdgeInsets.zero,
                                                visualDensity: VisualDensity.compact,
                                                onChanged: (bool? checked) {
                                                  setModalState(() {
                                                    if (checked == true) addedIngredients.add(ingredient);
                                                    else addedIngredients.removeWhere((item) => item['name'] == ingredient['name']);
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        )
                                    ],
                                  ),
                                ),

                              if (isByWeight)
                                Container(
                                  margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.withOpacity(0.3))),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.balance, color: Colors.purpleAccent, size: 20), const SizedBox(width: 8),
                                      Expanded(child: Text('Увага! Це вагова страва. Вказана ціна за $weightMeasure. Точна вартість буде розрахована після приготування.', style: const TextStyle(color: Colors.purpleAccent, fontSize: 13, fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),

                      // --- ФІКСОВАНА КНОПКА ЗНИЗУ ---
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        decoration: BoxDecoration(
                            color: sheetBgColor,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, -4))]
                        ),
                        child: SizedBox(
                          width: double.infinity, height: 56,
                          child: Consumer<CartProvider>(
                            builder: (context, cart, child) => ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: isOpen ? const Color(0xFFFFCD00) : (isDark ? Colors.grey[800] : Colors.grey[300]), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                              onPressed: !isOpen ? null : () {
                                dish['price'] = finalPrice;
                                dish['removed_ingredients'] = removedIngredients;
                                dish['added_ingredients'] = addedIngredients;
                                if (cart.addItem(dish)) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${dish['name']} додано в кошик!')));
                                } else {
                                  _showClearCartDialog(context, cart, dish);
                                }
                              },
                              child: Text(isOpen ? 'Додати • $priceText' : 'Ресторан зачинено', style: TextStyle(fontSize: 18, color: isOpen ? Colors.black87 : Colors.grey, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // =========================================================
    // 🔥 МАГІЧНИЙ БЛОК ДЛЯ АДАПТАЦІЇ ТЕМИ
    // =========================================================
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    final drawerBgColor = isDark ? const Color(0xFF1E1E1E).withOpacity(0.95) : Colors.white.withOpacity(0.9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white70 : Colors.grey[700];
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final chipBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    // =========================================================

    final bool isOpen = checkIsRestaurantOpen(_currentRestaurant);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dishesStream,
      builder: (context, snapshot) {
        List<Map<String, dynamic>> allDishes = [];
        List<String> restaurantCategories = [];

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          allDishes = snapshot.data!
              .where((dish) =>
          dish['is_available'] == true || dish['is_available'] == null)
              .toList();
          restaurantCategories =
              allDishes.map((d) => d['category']?.toString() ?? '').where((
                  c) => c.isNotEmpty).toSet().toList();

          if (_selectedCategory == null && widget.initialDish != null) {
            _selectedCategory = widget.initialDish!['category'];
          }
        }

        final currentCategory = _selectedCategory ??
            (restaurantCategories.isNotEmpty ? restaurantCategories.first : '');
        final filteredDishes = allDishes.where((d) =>
        d['category'] == currentCategory).toList();

        if (snapshot.hasData && widget.initialDish != null &&
            !_hasOpenedInitialDish) {
          _hasOpenedInitialDish = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDishDetails(context, widget.initialDish!, isOpen);
          });
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          // БІЧНЕ МЕНЮ (Drawer)
          drawer: SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                width: 220,
                margin: const EdgeInsets.only(top: 16, bottom: 16),
                decoration: BoxDecoration(
                  color: drawerBgColor, // 🔥 Адаптивний фон Drawer
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(5, 5))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Text('Меню закладу',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)), // 🔥 Адаптивний текст
                    ),
                    Divider(height: 1,
                        thickness: 1,
                        color: isDark ? Colors.white24 : Colors.black.withOpacity(0.05)),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: restaurantCategories.length,
                        itemBuilder: (context, index) {
                          final cat = restaurantCategories[index];
                          final isSelected = currentCategory == cat;
                          final emoji = widget.categoryEmojis?[cat] ?? '🍲';

                          return ListTile(
                            leading: Text(
                                emoji, style: const TextStyle(fontSize: 22)),
                            title: Text(cat, style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? const Color(0xFF005BBB)
                                    : textColor, // 🔥 Адаптивний текст
                                fontSize: 14)),
                            selected: isSelected,
                            selectedTileColor: const Color(0xFF005BBB)
                                .withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                            onTap: () {
                              setState(() => _selectedCategory = cat);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          // --- ОНОВЛЕНИЙ ПРОЗОРИЙ APPBAR ---
          appBar: AppBar(
            leading: Builder(
              builder: (ctx) =>
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => Navigator.pop(context),
                  ),
            ),
            title: Text(
              (_currentRestaurant['name'] ?? 'Ресторан').toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
            ),
            actions: [
              Consumer<CartProvider>(
                builder: (context, cart, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.shopping_cart),
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const CartScreen()))),
                      if (cart.items.isNotEmpty)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10)),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text('${cart.items.length}',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ),
                        )
                    ],
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          body: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                  image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
            ),
            child: Container(
              // ФІЛЬТР ЗАВЖДИ ЧОРНИЙ
              color: Colors.black.withOpacity(0.4),
              child: Column(
                children: [
                  SizedBox(height: MediaQuery
                      .of(context)
                      .padding
                      .top + kToolbarHeight),

                  if (!isOpen)
                    Container(width: double.infinity,
                        color: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        child: const Row(children: [
                          Icon(Icons.info_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(child: Text(
                              'Ресторан тимчасово не приймає замовлення',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold)))
                        ])),
                  if (isOpen && (_currentRestaurant['is_peak_hours'] == true))
                    Container(width: double.infinity,
                        color: Colors.orange[800],
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 16),
                        child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.local_fire_department, color: Colors
                                  .white, size: 20),
                              SizedBox(width: 8),
                              Expanded(child: Text(
                                  'У ресторані зараз високе навантаження. Час очікування замовлення може бути збільшено.',
                                  style: TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)))
                            ])),

                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Expanded(
                        child: Center(child: CircularProgressIndicator()))
                  else
                    if (allDishes.isEmpty)
                      const Expanded(child: Center(child: Text(
                          'Усі страви зараз розпродані', style: TextStyle(
                          fontSize: 16, color: Colors.white))))
                    else
                      ...[
                        // --- ГОРИЗОНТАЛЬНА СТРІЧКА КАТЕГОРІЙ ---
                        Container(
                          height: 60,
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 12.0, right: 8.0),
                                child: Builder(
                                  builder: (ctx) =>
                                      ActionChip(
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.grid_view_rounded,
                                                size: 20,
                                                color: textColor), // 🔥 Адаптивний текст
                                            const SizedBox(width: 6),
                                            Text('Меню', style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: textColor)), // 🔥 Адаптивний текст
                                          ],
                                        ),
                                        backgroundColor: chipBgColor, // 🔥 Адаптивний фон
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                20), side: BorderSide.none),
                                        onPressed: () =>
                                            Scaffold.of(ctx).openDrawer(),
                                      ),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: restaurantCategories.length,
                                  itemBuilder: (context, index) {
                                    final cat = restaurantCategories[index];
                                    final isSelected = currentCategory == cat;
                                    final emoji = widget.categoryEmojis?[cat] ??
                                        '🍲';

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0, vertical: 10.0),
                                      child: ChoiceChip(
                                        label: Text('$emoji $cat',
                                            style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? Colors.white
                                                    : textColor)), // 🔥 Адаптивний текст
                                        selected: isSelected,
                                        selectedColor: const Color(0xFF005BBB),
                                        backgroundColor: chipBgColor, // 🔥 Адаптивний фон
                                        side: BorderSide.none,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                20)),
                                        onSelected: (selected) {
                                          if (selected) setState(() =>
                                          _selectedCategory = cat);
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ------------------------------------------

                        // --- КЛАСИЧНИЙ СПИСОК СТРАВ ОДНІЄЇ КАТЕГОРІЇ ---
                        Expanded(
                          child: filteredDishes.isEmpty
                              ? const Center(child: Text('У цій категорії немає страв', style: TextStyle(color: Colors.white)))
                              : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                            itemCount: filteredDishes.length,
                            itemBuilder: (context, index) {
                              final dish = filteredDishes[index];
                              final isFav = _favoriteDishIds.contains(dish['id']);
                              final bool isByWeight = dish['is_by_weight'] ?? false;
                              final String weightMeasure = dish['weight_measure'] ?? '100 г';
                              final String priceText = isByWeight ? '${dish['price']} грн / $weightMeasure' : '${dish['price']} грн';
                              final bool hasModifiers = (dish['removable_ingredients'] != null && (dish['removable_ingredients'] as List).isNotEmpty) || (dish['addable_ingredients'] != null && (dish['addable_ingredients'] as List).isNotEmpty);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                                decoration: BoxDecoration(
                                  color: cardColor, // 🔥 Адаптивна картка
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: borderColor, width: 1.5), // 🔥 Адаптивна рамка
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _showDishDetails(context, dish, isOpen),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(dish['image_url'] ?? dish['image'] ?? '', width: 75, height: 75, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 75, height: 75, color: isDark ? Colors.grey[800] : Colors.grey[300]))
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(child: Text(dish['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor))), // 🔥 Адаптивний текст
                                                    GestureDetector(onTap: () => _toggleFavorite(dish['id']), child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : Colors.grey[400], size: 24)),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(dish['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: hintColor)), // 🔥 Адаптивний текст
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4,
                                                  children: [
                                                    Text(priceText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF005BBB))),
                                                    if (isByWeight) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.withOpacity(0.3))), child: const Text('Вагова', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)))
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              const SizedBox(height: 28),
                                              Consumer<CartProvider>(
                                                builder: (context, cart, child) => ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor: isOpen ? const Color(0xFFFFCD00) : (isDark ? Colors.grey[800] : Colors.grey[300]),
                                                      foregroundColor: isOpen ? Colors.black : Colors.grey,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                                      minimumSize: const Size(0, 32),
                                                      elevation: 0,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                                  ),
                                                  onPressed: !isOpen ? null : () {
                                                    if (hasModifiers) { _showDishDetails(context, dish, isOpen); } else {
                                                      if (cart.addItem(dish)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${dish['name']} додано в кошик!'), duration: const Duration(seconds: 1))); } else { _showClearCartDialog(context, cart, dish); }
                                                    }
                                                  },
                                                  child: const Text('Додати', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                ),
                                              ),
                                            ],
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
                      ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}