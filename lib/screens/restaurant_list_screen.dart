import 'dart:async';
import 'package:flutter/material.dart';
import '../core/supabase_service.dart';
import '../utils/restaurant_helper.dart';
import 'restaurant_menu_screen.dart';

class RestaurantListScreen extends StatefulWidget {
  final String initialCategory;

  const RestaurantListScreen({super.key, required this.initialCategory});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> with WidgetsBindingObserver {
  late String _selectedCategory;
  String _searchQuery = '';

  List<Map<String, dynamic>> _allRestaurants = [];
  List<Map<String, dynamic>> _allDishes = [];
  List<String> _categories = [];
  Map<String, String> _categoryEmojis = {'Всі': '🍽️'};
  bool _isLoading = true;

  StreamSubscription? _restaurantsSub;
  StreamSubscription? _dishesSub;
  StreamSubscription? _categoriesSub;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    WidgetsBinding.instance.addObserver(this);
    _setupStreams();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restaurantsSub?.cancel();
    _dishesSub?.cancel();
    _categoriesSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restaurantsSub?.cancel();
      _dishesSub?.cancel();
      _categoriesSub?.cancel();
      _setupStreams();
    }
  }

  void _setupStreams() {
    if (mounted) setState(() => _isLoading = true);

    _restaurantsSub = SupabaseService.client
        .from('restaurants')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (mounted) setState(() {
        _allRestaurants = data;
        _isLoading = false;
      });
    }, onError: (err) => debugPrint('Помилка потоку ресторанів: $err'));

    _dishesSub = SupabaseService.client
        .from('dishes')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (mounted) {
        setState(() {
          _allDishes = data;
          final uniqueCategories = _allDishes
              .map((d) => d['category']?.toString() ?? '')
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList();
          _categories = uniqueCategories;
          _isLoading = false;
        });
      }
    }, onError: (err) => debugPrint('Помилка потоку страв: $err'));

    _categoriesSub = SupabaseService.client
        .from('categories')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (mounted) {
        Map<String, String> emojis = {'Всі': '🍽️'};
        for (var row in data) {
          final name = row['name']?.toString() ?? '';
          final emoji = row['emoji']?.toString() ?? '';
          if (name.isNotEmpty && emoji.isNotEmpty) {
            emojis[name] = emoji;
          }
        }
        setState(() {
          _categoryEmojis = emojis;
        });
      }
    }, onError: (err) => debugPrint('Помилка потоку категорій: $err'));
  }

  void _navigateToRestaurant(Map<String, dynamic> restaurant, [Map<String, dynamic>? targetDish]) {
    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        RestaurantMenuScreen(
          restaurant: restaurant,
          initialDish: targetDish,
          initialCategory: _selectedCategory,
          categoryEmojis: _categoryEmojis,
        )));
  }

  void _showAllCategoriesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final chipBgColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100];
        final chipBorderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!;

        return Container(
          decoration: BoxDecoration(color: sheetBgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(10)))),
              Text('Усі категорії', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12, runSpacing: 12,
                children: [
                  FilterChip(
                    label: Text('🍽️ Всі заклади', style: TextStyle(fontWeight: FontWeight.w600, color: _selectedCategory == 'Всі' ? Colors.white : textColor)),
                    selected: _selectedCategory == 'Всі',
                    onSelected: (_) {
                      setState(() => _selectedCategory = 'Всі');
                      Navigator.pop(context);
                    },
                    backgroundColor: chipBgColor, selectedColor: const Color(0xFF005BBB),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _selectedCategory == 'Всі' ? Colors.transparent : chipBorderColor)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  ..._categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    final emoji = _categoryEmojis[cat] ?? '🍲';
                    return FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 6),
                          Text(cat, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : textColor)),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedCategory = cat);
                        Navigator.pop(context);
                      },
                      backgroundColor: chipBgColor, selectedColor: const Color(0xFF005BBB),
                      elevation: isSelected ? 4 : 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.transparent : chipBorderColor)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    );
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    final searchBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);
    final chipBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.85);

    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6);

    final query = _searchQuery.trim().toLowerCase();
    final bool isSearching = query.length >= 3;

    List<Map<String, dynamic>> foundRestaurants = [];
    List<Map<String, dynamic>> foundDishes = [];

    if (isSearching) {
      final searchWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      foundRestaurants = _allRestaurants.where((r) =>
          searchWords.every((word) => r['name'].toString().toLowerCase().contains(word))).toList();
      foundDishes = _allDishes.where((d) {
        if (d['is_available'] == false) return false;
        final searchableText = '${d['name'].toString().toLowerCase()} ${d['category'].toString().toLowerCase()}';
        if (d['name'].toString().toLowerCase().contains(query)) return true;
        return searchWords.every((word) => searchableText.contains(word));
      }).toList();
    }

    List<Map<String, dynamic>> filteredRestaurants = _allRestaurants.where((r) {
      final restaurantDishes = _allDishes.where((d) => d['restaurant_id'] == r['id']).toList();
      return _selectedCategory == 'Всі' || restaurantDishes.any((d) => d['category'] == _selectedCategory);
    }).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
            _selectedCategory == 'Всі' ? 'Всі заклади' : _selectedCategory,
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])
        ),
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
      ),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover)),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: SafeArea(
            bottom: false,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Пошук закладів та страв...',
                      hintStyle: TextStyle(color: hintColor),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF005BBB)),
                      suffixIcon: isSearching ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () {
                        setState(() => _searchQuery = '');
                        FocusScope.of(context).unfocus();
                      }) : null,
                      filled: true,
                      fillColor: searchBgColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),

                if (isSearching)
                  Expanded(
                    child: (foundRestaurants.isEmpty && foundDishes.isEmpty)
                        ? Center(child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                        child: Text('За запитом "$_searchQuery" нічого не знайдено', style: TextStyle(fontWeight: FontWeight.bold, color: textColor))
                    ))
                        : ListView(
                      // 🔥 Збільшили відступ знизу для результатів пошуку
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 160),
                      children: [
                        if (foundRestaurants.isNotEmpty) ...[
                          const Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 4),
                              child: Text('Заклади', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))),
                          ...foundRestaurants.map((r) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor, width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(r['image_url'] ?? '', width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey[300], child: const Icon(Icons.restaurant, color: Colors.grey)))),
                                title: Text(r['name'], style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                                subtitle: const Text('Перейти до меню', style: TextStyle(color: Color(0xFF005BBB), fontSize: 12)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                onTap: () => _navigateToRestaurant(r),
                              ),
                            ),
                          )).toList(),
                        ],

                        if (foundDishes.isNotEmpty) ...[
                          const Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 4),
                              child: Text('Страви', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))),
                          ...foundDishes.map((dish) {
                            final restaurant = _allRestaurants.firstWhere((r) => r['id'] == dish['restaurant_id'], orElse: () => {});
                            final bool isByWeight = dish['is_by_weight'] ?? false;
                            final String priceText = isByWeight ? '${dish['price']} грн / ${dish['weight_measure'] ?? '100 г'}' : '${dish['price']} грн';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: borderColor, width: 1.5),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(dish['image_url'] ?? '', width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey[300], child: const Icon(Icons.fastfood, color: Colors.grey)))),
                                  title: Text(dish['name'], style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                                  subtitle: Text('$priceText • з ${restaurant['name'] ?? 'Невідомо'}', style: TextStyle(color: hintColor)),
                                  trailing: const Icon(Icons.add_shopping_cart, color: Color(0xFF005BBB)),
                                  onTap: () {
                                    if (restaurant.isNotEmpty) _navigateToRestaurant(restaurant, dish);
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    ),
                  )
                else
                  ...[
                    Builder(
                        builder: (context) {
                          List<String> visibleCategories = _categories.take(4).toList();

                          if (_selectedCategory != 'Всі' && !visibleCategories.contains(_selectedCategory)) {
                            if (visibleCategories.length == 4) {
                              visibleCategories[3] = _selectedCategory;
                            } else {
                              visibleCategories.add(_selectedCategory);
                            }
                          }

                          return SizedBox(
                            height: 50,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: visibleCategories.length + 1,
                              itemBuilder: (context, index) {

                                if (index == 0) {
                                  final isAllSelected = _selectedCategory == 'Всі';
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                                    child: ActionChip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.grid_view_rounded, size: 18, color: isAllSelected ? Colors.white : textColor),
                                          const SizedBox(width: 6),
                                          Text('Усі', style: TextStyle(fontWeight: FontWeight.w600, color: isAllSelected ? Colors.white : textColor)),
                                        ],
                                      ),
                                      onPressed: _showAllCategoriesBottomSheet,
                                      backgroundColor: isAllSelected ? const Color(0xFF005BBB) : chipBgColor,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isAllSelected ? Colors.transparent : borderColor)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  );
                                }

                                final cat = visibleCategories[index - 1];
                                final isSelected = _selectedCategory == cat;
                                final emoji = _categoryEmojis[cat] ?? '🍲';

                                return Padding(
                                  padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                                  child: FilterChip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(emoji, style: const TextStyle(fontSize: 16)),
                                        const SizedBox(width: 6),
                                        Text(cat, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : textColor)),
                                      ],
                                    ),
                                    selected: isSelected,
                                    onSelected: (bool selected) => setState(() => _selectedCategory = selected ? cat : 'Всі'),
                                    backgroundColor: chipBgColor,
                                    selectedColor: const Color(0xFF005BBB),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.transparent : borderColor)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                );
                              },
                            ),
                          );
                        }
                    ),

                    // 🔥 ГОЛОВНА СІТКА ЗІ ЗБІЛЬШЕНИМ ВІДСТУПОМ ЗНИЗУ
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 160, left: 16, right: 16), // 🔥 Ось він, рятівний 160!
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: filteredRestaurants.length,
                        itemBuilder: (context, index) {
                          final r = filteredRestaurants[index];
                          final bool isOpen = checkIsRestaurantOpen(r);

                          return Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor, width: 1.5),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _navigateToRestaurant(r),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                            child: Image.network(
                                                r['image_url'] ?? '',
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(color: Colors.grey[300], child: const Icon(Icons.restaurant, color: Colors.grey))
                                            ),
                                          ),
                                          if (!isOpen)
                                            Positioned(
                                              top: 8, left: 8, right: 8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                                                child: const Text('Зачинено', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                              ),
                                            )
                                          else if (r['is_peak_hours'] == true)
                                            Positioned(
                                              top: 8, left: 8, right: 8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                                                child: const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.local_fire_department, color: Colors.white, size: 12),
                                                    SizedBox(width: 4),
                                                    Text('Висока нагрузка', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                                r['name'],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: textColor)
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.star_rounded, color: Color(0xFFFFCD00), size: 14),
                                                const SizedBox(width: 2),
                                                Text('${r['rating'] ?? '5.0'}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                                                const SizedBox(width: 6),
                                                Text('•', style: TextStyle(color: hintColor, fontSize: 12)),
                                                const SizedBox(width: 6),
                                                const Icon(Icons.access_time_rounded, color: Colors.grey, size: 12),
                                                const SizedBox(width: 2),
                                                Expanded(
                                                  child: Text(
                                                      '${r['time'] ?? '30 хв'}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: hintColor, fontWeight: FontWeight.w500, fontSize: 12)
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
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
      ),
    );
  }
}