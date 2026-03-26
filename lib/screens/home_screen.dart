import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/supabase_service.dart';
import 'restaurant_list_screen.dart';
import 'restaurant_menu_screen.dart'; // 🔥 ДОБАВЛЕНО: Импорт экрана меню ресторана

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = 'Гість';

  List<Map<String, dynamic>> _foodCategories = [];
  List<Map<String, dynamic>> _drinkCategories = [];

  String? _activeOverlayType;
  bool _isLoading = true;

  // =========================================================
  // 🔥 ПЕРЕМЕННЫЕ ДЛЯ БАННЕРОВ
  // =========================================================
  List<Map<String, dynamic>> _banners = [];
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_bannerController.hasClients && _banners.isNotEmpty) {
        int nextPageIndex = _bannerController.page!.round() + 1;
        if (nextPageIndex >= _banners.length) {
          _bannerController.animateToPage(0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
        } else {
          _bannerController.animateToPage(nextPageIndex, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
        }
      }
    });
  }

  Future<void> _fetchInitialData() async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        final profile = await SupabaseService.client
            .from('profiles')
            .select('full_name')
            .eq('user_id', user.id)
            .maybeSingle();

        if (profile != null && profile['full_name'] != null) {
          _userName = profile['full_name'].toString().split(' ')[0];
        }
      }

      final data = await SupabaseService.client.from('categories').select().order('name');
      List<Map<String, dynamic>> food = [];
      List<Map<String, dynamic>> drinks = [];

      for (var cat in data) {
        final section = cat['section']?.toString() ?? '';
        if (section == 'Їжа') {
          food.add(cat);
        } else if (section == 'Алкогольні напої' || section == 'Безалкогольні напої') {
          drinks.add(cat);
        } else {
          food.add(cat);
        }
      }

      // 🔥 ЗАГРУЗКА БАННЕРОВ
      try {
        final bannerData = await SupabaseService.client.from('banners').select();
        List<Map<String, dynamic>> fetchedBanners = List<Map<String, dynamic>>.from(bannerData);
        fetchedBanners.shuffle();
        _banners = fetchedBanners;
      } catch (e) {
        debugPrint('Помилка завантаження банерів: $e');
      }

      if (mounted) {
        setState(() {
          _foodCategories = food;
          _drinkCategories = drinks;
          _isLoading = false;
        });

        if (_banners.isNotEmpty) {
          _startBannerTimer();
        }
      }
    } catch (e) {
      debugPrint('Помилка завантаження головного екрана: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToRestaurantList(String categoryName) {
    if (_activeOverlayType != null) {
      setState(() => _activeOverlayType = null);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestaurantListScreen(initialCategory: categoryName),
      ),
    );
  }

  // =========================================================
  // 🔥 ЛОГИКА НАЖАТИЯ НА БАННЕР
  // =========================================================
  Future<void> _onBannerTapped(Map<String, dynamic> banner) async {
    final restaurantId = banner['restaurant_id'];

    // Если у баннера нет привязки к ресторану - открываем общий список
    if (restaurantId == null || restaurantId.toString().isEmpty) {
      _navigateToRestaurantList('Всі');
      return;
    }

    // Показываем индикатор загрузки, пока тянем данные ресторана
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF005BBB))),
    );

    try {
      // Ищем ресторан в базе
      final restaurantData = await SupabaseService.client
          .from('restaurants')
          .select()
          .eq('id', restaurantId)
          .single();

      if (!mounted) return;
      Navigator.pop(context); // Закрываем лоадер

      // Открываем меню конкретного ресторана
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
      Navigator.pop(context); // Закрываем лоадер
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити заклад 😔')),
      );
      debugPrint('Ошибка при переходе к ресторану из баннера: $e');
    }
  }

  Widget _buildCategoryOverlay() {
    if (_activeOverlayType == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnBgColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final btnBorderColor = isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.8);
    final textColor = isDark ? Colors.white : Colors.black87;

    String title = _activeOverlayType == 'food' ? 'Поїсти' : 'Випити';
    String allEmoji = _activeOverlayType == 'food' ? '🍽️' : '🥂';
    List<Map<String, dynamic>> categories = _activeOverlayType == 'food' ? _foodCategories : _drinkCategories;

    Widget buildCatButton(String displayName, String navigateName, String emoji) {
      return InkWell(
        onTap: () => _navigateToRestaurantList(navigateName),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: btnBgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: btnBorderColor, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _activeOverlayType = null),
      child: Container(
        color: Colors.black.withOpacity(0.2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                margin: const EdgeInsets.all(20),
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                            'Що саме?',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 10)]
                            )
                        ),
                        IconButton(
                          onPressed: () => setState(() => _activeOverlayType = null),
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    buildCatButton('Всі $title', 'Всі', allEmoji),
                    const SizedBox(height: 12),

                    ...List.generate((categories.length / 2).ceil(), (index) {
                      int firstItemIndex = index * 2;
                      int secondItemIndex = firstItemIndex + 1;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: buildCatButton(
                                  categories[firstItemIndex]['name'] ?? 'Категорія',
                                  categories[firstItemIndex]['name'] ?? 'Категорія',
                                  categories[firstItemIndex]['emoji'] ?? '🍲'
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: secondItemIndex < categories.length
                                  ? buildCatButton(
                                  categories[secondItemIndex]['name'] ?? 'Категорія',
                                  categories[secondItemIndex]['name'] ?? 'Категорія',
                                  categories[secondItemIndex]['emoji'] ?? '🍲'
                              )
                                  : const SizedBox(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                bottom: false,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Привіт, $_userName! 👋',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Чого б тобі хотілось саме зараз?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: InkWell(
                                      onTap: () => setState(() => _activeOverlayType = 'food'),
                                      borderRadius: BorderRadius.circular(28),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(28),
                                          border: Border.all(color: borderColor, width: 1.5),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('🍕', style: TextStyle(fontSize: 50)),
                                            const SizedBox(height: 12),
                                            Text('Смачно\nпоїсти', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, height: 1.1)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: InkWell(
                                      onTap: () => setState(() => _activeOverlayType = 'drink'),
                                      borderRadius: BorderRadius.circular(28),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(28),
                                          border: Border.all(color: borderColor, width: 1.5),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('🍹', style: TextStyle(fontSize: 50)),
                                            const SizedBox(height: 12),
                                            Text('Щось\nвипити', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor, height: 1.1)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            InkWell(
                              onTap: () => _navigateToRestaurantList('Всі'),
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: borderColor, width: 1.5),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('🗺️', style: TextStyle(fontSize: 40)),
                                    const SizedBox(width: 16),
                                    Text(
                                        'Або переглянути\nусі заклади одразу',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ===================================
                            // 🔥 ДИНАМИЧЕСКИЕ БАННЕРЫ С КЛИКОМ
                            // ===================================
                            if (_banners.isNotEmpty)
                              SizedBox(
                                height: 140,
                                child: PageView.builder(
                                  controller: _bannerController,
                                  itemCount: _banners.length,
                                  itemBuilder: (context, index) {
                                    final banner = _banners[index];
                                    final String? imageUrl = banner['image_url'];
                                    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

                                    // 🔥 Обернули баннер в GestureDetector
                                    return GestureDetector(
                                      onTap: () => _onBannerTapped(banner),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        decoration: BoxDecoration(
                                          gradient: hasImage ? null : LinearGradient(
                                            colors: [const Color(0xFF005BBB).withOpacity(0.8), const Color(0xFF005BBB).withOpacity(0.4)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          image: hasImage
                                              ? DecorationImage(
                                            image: NetworkImage(imageUrl),
                                            fit: BoxFit.cover,
                                            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken),
                                          )
                                              : null,
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
                                        ),
                                        child: Row(
                                          children: [
                                            if (!hasImage)
                                              const Text('🎁', style: TextStyle(fontSize: 40)),
                                            if (!hasImage)
                                              const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      banner['title'] ?? '',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      banner['subtitle'] ?? '',
                                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _activeOverlayType != null ? _buildCategoryOverlay() : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}