import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> with WidgetsBindingObserver {
  List<String> _categories = [];
  List<Map<String, dynamic>> _dishes = [];
  String? _selectedCategory;

  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMoreDishes = true;
  int _currentOffset = 0;
  final int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _realtimeChannel;

  bool _hasOpenedInitialDish = false;
  List<dynamic> _favoriteDishIds = [];
  late Map<String, dynamic> _currentRestaurant;
  StreamSubscription? _restaurantSub;

  @override
  void initState() {
    super.initState();
    _currentRestaurant = widget.restaurant;
    WidgetsBinding.instance.addObserver(this);

    _scrollController.addListener(_onScroll);

    _restaurantSub = SupabaseService.client
        .from('restaurants')
        .stream(primaryKey: ['id'])
        .eq('id', _currentRestaurant['id'])
        .listen((data) {
      if (data.isNotEmpty && mounted) setState(() => _currentRestaurant = data.first);
    });

    _loadFavorites();
    _initDataAndRealtime();
  }

  Future<void> _initDataAndRealtime() async {
    await _fetchCategories();
    _setupRealtimeUpdates();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadDishesForCategory();
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await SupabaseService.client
          .from('dishes')
          .select('category')
          .eq('restaurant_id', _currentRestaurant['id'])
          .or('is_available.eq.true,is_available.is.null');

      final Set<String> uniqueCats = {};
      for (var item in res) {
        if (item['category'] != null && item['category'].toString().isNotEmpty) {
          uniqueCats.add(item['category'].toString().trim());
        }
      }

      if (mounted) {
        setState(() {
          _categories = uniqueCats.toList();

          if (_categories.isNotEmpty) {
            _selectedCategory = widget.initialCategory ?? (widget.initialDish != null ? widget.initialDish!['category'] : _categories.first);
            if (!_categories.contains(_selectedCategory)) _selectedCategory = _categories.first;

            _loadDishesForCategory(isRefresh: true);
          } else {
            _isLoadingInitial = false;
          }
        });
      }
    } catch (e) {
      debugPrint('Помилка завантаження категорій: $e');
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _loadDishesForCategory({bool isRefresh = false}) async {
    if (_selectedCategory == null) return;

    if (isRefresh) {
      setState(() {
        _isLoadingInitial = true;
        _currentOffset = 0;
        _hasMoreDishes = true;
        _dishes.clear();
      });
    } else {
      if (!_hasMoreDishes || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final res = await SupabaseService.client
          .from('dishes')
          .select()
          .eq('restaurant_id', _currentRestaurant['id'])
          .eq('category', _selectedCategory!)
          .or('is_available.eq.true,is_available.is.null')
          .order('name')
          .range(_currentOffset, _currentOffset + _pageSize - 1);

      if (mounted) {
        setState(() {
          if (res.length < _pageSize) {
            _hasMoreDishes = false;
          }
          _dishes.addAll(res);
          _currentOffset += res.length;
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });

        if (widget.initialDish != null && !_hasOpenedInitialDish) {
          _hasOpenedInitialDish = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDishDetails(context, widget.initialDish!, checkIsRestaurantOpen(_currentRestaurant));
          });
        }
      }
    } catch (e) {
      debugPrint('Помилка завантаження страв: $e');
      if (mounted) setState(() { _isLoadingInitial = false; _isLoadingMore = false; });
    }
  }

  void _changeCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _loadDishesForCategory(isRefresh: true);
  }

  void _setupRealtimeUpdates() {
    _realtimeChannel = SupabaseService.client.channel('public:dishes_updates:${_currentRestaurant['id']}');
    _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dishes',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'restaurant_id', value: _currentRestaurant['id']),
        callback: (payload) {
          if (!mounted) return;

          final eventType = payload.eventType;

          if (eventType == PostgresChangeEvent.update) {
            final updatedDish = payload.newRecord;
            final index = _dishes.indexWhere((d) => d['id'] == updatedDish['id']);

            if (index != -1) {
              if (updatedDish['is_available'] == false) {
                setState(() => _dishes.removeAt(index));
              } else {
                setState(() => _dishes[index] = updatedDish);
              }
            } else {
              if ((updatedDish['is_available'] == true || updatedDish['is_available'] == null) &&
                  updatedDish['category'] == _selectedCategory) {
                _loadDishesForCategory(isRefresh: true);
              }
            }
          }
          else if (eventType == PostgresChangeEvent.insert || eventType == PostgresChangeEvent.delete) {
            _loadDishesForCategory(isRefresh: true);
          }
        }
    ).subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _restaurantSub?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCategories();
    }
  }

  Future<void> _loadFavorites() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await SupabaseService.client.from('favorites').select('dish_id').eq('user_id', user.id);
      if (mounted) setState(() => _favoriteDishIds = res.map((f) => f['dish_id']).toList());
    } catch (e) {
      debugPrint('Помилка завантаження улюблених: $e');
    }
  }

  Future<void> _toggleFavorite(dynamic dishId) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Увійдіть, щоб зберігати страви')));
      return;
    }
    final isFav = _favoriteDishIds.contains(dishId);
    setState(() {
      if (isFav) _favoriteDishIds.remove(dishId);
      else _favoriteDishIds.add(dishId);
    });
    try {
      if (isFav) {
        await SupabaseService.client.from('favorites').delete().eq('user_id', user.id).eq('dish_id', dishId);
      } else {
        await SupabaseService.client.from('favorites').insert({'user_id': user.id, 'dish_id': dishId});
      }
    } catch (e) {
      setState(() {
        if (isFav) _favoriteDishIds.add(dishId);
        else _favoriteDishIds.remove(dishId);
      });
    }
  }

  void _showClearCartDialog(BuildContext context, CartProvider cart, Map<String, dynamic> dish) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Зміна закладу'),
        content: const Text('У вашому кошику вже є страви з іншого ресторану. Очистити кошик, щоб додати цю страву?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () {
                cart.clear();
                cart.addItem(dish);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Кошик очищено. ${dish['name']} додано!')));
              },
              child: const Text('Очистити кошик', style: TextStyle(color: Colors.red))
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.grey[800];
    final accordionBgColor = isDark ? Colors.black.withOpacity(0.3) : Colors.grey[50];
    final accordionBorderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: StatefulBuilder(
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

                return Dialog(
                  backgroundColor: sheetBgColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  Image.network(
                                      dish['image_url'] ?? dish['image'] ?? '',
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(height: 200, color: accordionBgColor)
                                  ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: Text(dish['name'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2, color: textColor))),
                                        const SizedBox(width: 8),
                                        GestureDetector(onTap: () { _toggleFavorite(dish['id']); setModalState(() {}); }, child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : Colors.grey[400], size: 28)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(priceText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF005BBB))),
                                    const SizedBox(height: 12),
                                    Text(dish['description'] ?? 'Опис відсутній', style: TextStyle(fontSize: 15, height: 1.4, color: subtitleColor)),

                                    if (removableList.isNotEmpty || addableList.isNotEmpty) const SizedBox(height: 24),

                                    if (removableList.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(color: accordionBgColor, border: Border.all(color: accordionBorderColor), borderRadius: BorderRadius.circular(16)),
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

                                    if (addableList.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(color: accordionBgColor, border: Border.all(color: accordionBorderColor), borderRadius: BorderRadius.circular(16)),
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
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: sheetBgColor,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, -4))]
                        ),
                        child: SizedBox(
                          width: double.infinity, height: 50,
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
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(isOpen ? 'Додати • $priceText' : 'Ресторан зачинено', style: TextStyle(fontSize: 18, color: isOpen ? Colors.black87 : Colors.grey, fontWeight: FontWeight.w900))
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    final drawerBgColor = isDark ? const Color(0xFF1E1E1E).withOpacity(0.95) : Colors.white.withOpacity(0.9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white70 : Colors.grey[700];
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final chipBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);

    final bool isOpen = checkIsRestaurantOpen(_currentRestaurant);

    return Scaffold(
      extendBodyBehindAppBar: true,
      drawer: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: 220,
            margin: const EdgeInsets.only(top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: drawerBgColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(5, 5))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Text('Меню закладу', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                ),
                Divider(height: 1, thickness: 1, color: isDark ? Colors.white24 : Colors.black.withOpacity(0.05)),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat;
                      final emoji = widget.categoryEmojis?[cat] ?? '🍲';

                      return ListTile(
                        leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                        title: Text(cat, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? const Color(0xFF005BBB) : textColor, fontSize: 14)),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF005BBB).withOpacity(0.1),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        onTap: () {
                          _changeCategory(cat);
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

      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(icon: const Icon(Icons.arrow_back_ios_new), onPressed: () => Navigator.pop(context)),
        ),
        title: Text(
          (_currentRestaurant['name'] ?? 'Ресторан').toUpperCase(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2, shadows: [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))]),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.7), Colors.transparent]),
          ),
        ),
        actions: [
          Consumer<CartProvider>(
            builder: (context, cart, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.shopping_cart), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))),
                  if (cart.items.isNotEmpty)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text('${cart.items.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

              if (!isOpen)
                Container(width: double.infinity, color: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: const Row(children: [Icon(Icons.info_outline, color: Colors.white), SizedBox(width: 8), Expanded(child: Text('Ресторан тимчасово не приймає замовлення', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]
                    )),
              if (isOpen && (_currentRestaurant['is_peak_hours'] == true))
                Container(width: double.infinity, color: Colors.orange[800], padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.local_fire_department, color: Colors.white, size: 20), SizedBox(width: 8), Expanded(child: Text('У ресторані зараз високе навантаження. Час очікування замовлення може бути збільшено.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)))]
                    )),

              if (_isLoadingInitial)
              // 🔥 ТУТ ВИКЛИКАЄТЬСЯ НАША НОВА АНІМАЦІЯ (ВЕЛИКА)
                const Expanded(child: _FoodLoadingAnimation(size: 60))
              else if (_categories.isEmpty)
                const Expanded(child: Center(child: Text('Меню наразі порожнє', style: TextStyle(fontSize: 16, color: Colors.white))))
              else
                ...[
                  Container(
                    height: 60, color: Colors.transparent,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                          child: Builder(
                            builder: (ctx) => ActionChip(
                              label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.grid_view_rounded, size: 20, color: textColor), const SizedBox(width: 6), Text('Меню', style: TextStyle(fontWeight: FontWeight.bold, color: textColor))]),
                              backgroundColor: chipBgColor, elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                              onPressed: () => Scaffold.of(ctx).openDrawer(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              final isSelected = _selectedCategory == cat;
                              final emoji = widget.categoryEmojis?[cat] ?? '🍲';

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 10.0),
                                child: ChoiceChip(
                                  label: Text('$emoji $cat', style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : textColor)),
                                  selected: isSelected, selectedColor: const Color(0xFF005BBB), backgroundColor: chipBgColor, side: BorderSide.none, elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  onSelected: (selected) { if (selected) _changeCategory(cat); },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: _dishes.isEmpty
                        ? const Center(child: Text('У цій категорії немає страв', style: TextStyle(color: Colors.white)))
                        : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      itemCount: _dishes.length + (_hasMoreDishes ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _dishes.length) {
                          // 🔥 ТУТ АНІМАЦІЯ МАЛЕНЬКА (ДЛЯ ПАГІНАЦІЇ)
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: _FoodLoadingAnimation(size: 35),
                          );
                        }

                        final dish = _dishes[index];
                        final isFav = _favoriteDishIds.contains(dish['id']);
                        final bool isByWeight = dish['is_by_weight'] ?? false;
                        final String weightMeasure = dish['weight_measure'] ?? '100 г';
                        final String priceText = isByWeight ? '${dish['price']} грн / $weightMeasure' : '${dish['price']} грн';
                        final bool hasModifiers = (dish['removable_ingredients'] != null && (dish['removable_ingredients'] as List).isNotEmpty) || (dish['addable_ingredients'] != null && (dish['addable_ingredients'] as List).isNotEmpty);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                          decoration: BoxDecoration(
                            color: cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor, width: 1.5),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                                              Expanded(child: Text(dish['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor))),
                                              GestureDetector(onTap: () => _toggleFavorite(dish['id']), child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : Colors.grey[400], size: 24)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(dish['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: hintColor)),
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
  }
}

// ============================================================================
// 🔥 КАСТОМНА АНІМАЦІЯ ЗАВАНТАЖЕННЯ
// ============================================================================
class _FoodLoadingAnimation extends StatefulWidget {
  final double size;
  const _FoodLoadingAnimation({this.size = 60});

  @override
  State<_FoodLoadingAnimation> createState() => _FoodLoadingAnimationState();
}

class _FoodLoadingAnimationState extends State<_FoodLoadingAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _emojis = ['🍕', '🍣', '🍔', '🥗', '🍩', '🍜', '🍟'];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller.reverse();
        } else if (status == AnimationStatus.dismissed) {
          if (mounted) {
            setState(() {
              _currentIndex = (_currentIndex + 1) % _emojis.length;
            });
            _controller.forward();
          }
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.7 + (_controller.value * 0.5),
            child: Opacity(
              opacity: 0.4 + (_controller.value * 0.6),
              child: Text(_emojis[_currentIndex], style: TextStyle(fontSize: widget.size)),
            ),
          );
        },
      ),
    );
  }
}