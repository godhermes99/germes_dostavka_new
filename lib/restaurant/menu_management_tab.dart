<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/supabase_service.dart';

// ============================================================================
// УПРАВЛІННЯ МЕНЮ РЕСТОРАНУ
// ============================================================================
class RestaurantMenuManager extends StatefulWidget {
  final dynamic restaurantId;
  const RestaurantMenuManager({super.key, required this.restaurantId});

  @override
  State<RestaurantMenuManager> createState() => _RestaurantMenuManagerState();
}

class _RestaurantMenuManagerState extends State<RestaurantMenuManager> with AutomaticKeepAliveClientMixin {
  final List<String> _sections = ['Їжа', 'Безалкогольні напої', 'Алкогольні напої'];
  String _selectedCategory = 'Всі';
  String _searchQuery = '';
  late Stream<List<Map<String, dynamic>>> _dishesStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dishesStream = SupabaseService.client
        .from('dishes')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', widget.restaurantId)
        .order('name');
  }

  void _showEditDishDialog({Map<String, dynamic>? dish, required List<Map<String, dynamic>> globalCategoriesData}) {
    final isNew = dish == null;
    final nameCtrl = TextEditingController(text: dish?['name'] ?? '');
    final descCtrl = TextEditingController(text: dish?['description'] ?? '');
    final priceCtrl = TextEditingController(text: dish?['price']?.toString() ?? '');
    final imageCtrl = TextEditingController(text: dish?['image'] ?? '');

    bool isByWeight = dish?['is_by_weight'] ?? false;
    final weightMeasureCtrl = TextEditingController(text: dish?['weight_measure'] ?? '100 г');

    // --- ЗМІННІ ДЛЯ МОДИФІКАТОРІВ ---
    List<String> removableList = List<String>.from(dish?['removable_ingredients'] ?? []);
    List<Map<String, dynamic>> addableList = List<Map<String, dynamic>>.from(dish?['addable_ingredients'] ?? []);

    final removeInputCtrl = TextEditingController();
    final addNameCtrl = TextEditingController();
    final addPriceCtrl = TextEditingController();
    // --------------------------------

    String selectedSection = dish?['section'] ?? _sections.first;

    List<String> getFilteredCategories(String section) {
      return globalCategoriesData.where((c) => c['section'] == section).map((c) => c['name'].toString()).toList();
    }

    List<String> currentFilteredCats = getFilteredCategories(selectedSection);
    String selectedCat = dish?['category'] ?? (currentFilteredCats.isNotEmpty ? currentFilteredCats.first : '');

    if (selectedCat.isNotEmpty && !currentFilteredCats.contains(selectedCat)) {
      currentFilteredCats.add(selectedCat);
    }

    bool isAvailable = dish?['is_available'] ?? true;
    bool isUploadingImage = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(isNew ? 'Нова страва' : 'Редагувати страву'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                          if (image != null) {
                            setDialogState(() => isUploadingImage = true);
                            try {
                              final bytes = await image.readAsBytes();
                              final fileExt = image.name.split('.').last;
                              final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                              await SupabaseService.client.storage.from('dish_images').uploadBinary(fileName, bytes);
                              final publicUrl = SupabaseService.client.storage.from('dish_images').getPublicUrl(fileName);
                              setDialogState(() { imageCtrl.text = publicUrl; isUploadingImage = false; });
                            } catch (e) {
                              setDialogState(() => isUploadingImage = false);
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
                            }
                          }
                        },
                        child: Container(
                          height: 150, width: double.infinity,
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), image: imageCtrl.text.isNotEmpty ? DecorationImage(image: NetworkImage(imageCtrl.text), fit: BoxFit.contain) : null, border: Border.all(color: Colors.grey[400]!)),
                          child: isUploadingImage ? const Center(child: CircularProgressIndicator()) : (imageCtrl.text.isEmpty ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height: 8), Text('Фото', style: TextStyle(color: Colors.grey))]) : Container(alignment: Alignment.bottomRight, padding: const EdgeInsets.all(8), child: const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.edit, size: 20, color: Colors.black)))),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Назва')),
                      TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Склад / Опис'), maxLines: 2),
                      TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Ціна (грн)'), keyboardType: TextInputType.number),
                      const SizedBox(height: 16),

                      Container(
                        decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple[200]!)),
                        child: Column(
                          children: [
                            SwitchListTile(title: const Text('Продається на вагу', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)), subtitle: const Text('Ціна залежатиме від ваги', style: TextStyle(fontSize: 12)), value: isByWeight, onChanged: (val) => setDialogState(() => isByWeight = val), activeColor: Colors.purple),
                            if (isByWeight) Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16), child: TextField(controller: weightMeasureCtrl, decoration: const InputDecoration(labelText: 'Одиниця виміру (напр. 100 г)', filled: true, fillColor: Colors.white))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ========================================================
                      // БЛОК: МОДИФІКАТОРИ ІНГРЕДІЄНТІВ
                      // ========================================================
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent), borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          title: const Text('🍔 Модифікатори інгредієнтів', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            // 1. ЩО МОЖНА ПРИБРАТИ
                            const Align(alignment: Alignment.centerLeft, child: Text('Можна прибрати (безкоштовно):', style: TextStyle(fontWeight: FontWeight.bold))),
                            Row(
                              children: [
                                Expanded(child: TextField(controller: removeInputCtrl, decoration: const InputDecoration(hintText: 'напр. Без цибулі', isDense: true))),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.redAccent),
                                  onPressed: () {
                                    if (removeInputCtrl.text.isNotEmpty) {
                                      setDialogState(() { removableList.add(removeInputCtrl.text.trim()); removeInputCtrl.clear(); });
                                    }
                                  },
                                )
                              ],
                            ),
                            if (removableList.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: removableList.map((item) => Chip(
                                  label: Text(item, style: const TextStyle(fontSize: 12)),
                                  onDeleted: () => setDialogState(() => removableList.remove(item)),
                                  backgroundColor: Colors.red[50], deleteIconColor: Colors.red,
                                )).toList(),
                              ),

                            const Divider(height: 24),

                            // 2. ЩО МОЖНА ДОДАТИ
                            const Align(alignment: Alignment.centerLeft, child: Text('Можна додати (за доплату):', style: TextStyle(fontWeight: FontWeight.bold))),
                            Row(
                              children: [
                                Expanded(flex: 2, child: TextField(controller: addNameCtrl, decoration: const InputDecoration(hintText: 'напр. Сир', isDense: true))),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: TextField(controller: addPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Ціна', isDense: true))),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.green),
                                  onPressed: () {
                                    if (addNameCtrl.text.isNotEmpty && addPriceCtrl.text.isNotEmpty) {
                                      setDialogState(() {
                                        addableList.add({ 'name': addNameCtrl.text.trim(), 'price': double.tryParse(addPriceCtrl.text.trim()) ?? 0 });
                                        addNameCtrl.clear(); addPriceCtrl.clear();
                                      });
                                    }
                                  },
                                )
                              ],
                            ),
                            if (addableList.isNotEmpty)
                              Column(
                                  children: addableList.map((item) => Card(
                                      color: Colors.green[50], margin: const EdgeInsets.symmetric(vertical: 4),
                                      child: ListTile(
                                        dense: true,
                                        title: Text(item['name']), trailing: Row(mainAxisSize: MainAxisSize.min, children: [ Text('+${item['price']} грн', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), onPressed: () => setDialogState(() => addableList.remove(item))) ]),
                                      )
                                  )).toList()
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ========================================================

                      DropdownButtonFormField<String>(
                        value: _sections.contains(selectedSection) ? selectedSection : _sections.first,
                        decoration: const InputDecoration(labelText: 'Тип меню (Розділ)'),
                        items: _sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) { setDialogState(() { selectedSection = val!; currentFilteredCats = getFilteredCategories(selectedSection); selectedCat = currentFilteredCats.isNotEmpty ? currentFilteredCats.first : ''; }); },
                      ),
                      const SizedBox(height: 10),

                      if (currentFilteredCats.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: selectedCat.isEmpty ? null : selectedCat, decoration: const InputDecoration(labelText: 'Категорія'),
                          items: currentFilteredCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) => setDialogState(() => selectedCat = val!),
                        )
                      else
                        Container(padding: const EdgeInsets.all(8), color: Colors.red[50], child: Text('У розділі "$selectedSection" ще немає категорій.', style: const TextStyle(color: Colors.red, fontSize: 12))),

                      const SizedBox(height: 10),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Доступно'), value: isAvailable, onChanged: (val) => setDialogState(() => isAvailable = val), activeColor: Colors.green),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty || selectedCat.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заповніть назву, ціну та категорію!')));
                        return;
                      }

                      final dishData = {
                        'restaurant_id': widget.restaurantId,
                        'name': nameCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'price': double.tryParse(priceCtrl.text.trim()) ?? 0.0,
                        'section': selectedSection,
                        'category': selectedCat,
                        'image': imageCtrl.text.trim(),
                        'is_available': isAvailable,
                        'is_by_weight': isByWeight,
                        'weight_measure': isByWeight ? weightMeasureCtrl.text.trim() : null,
                        // --- ЗБЕРІГАЄМО МОДИФІКАТОРИ В БАЗУ ---
                        'removable_ingredients': removableList,
                        'addable_ingredients': addableList,
                        // -------------------------------------
                      };

                      try {
                        if (isNew) {
                          await SupabaseService.client.from('dishes').insert(dishData);
                        } else {
                          await SupabaseService.client.from('dishes').update(dishData).eq('id', dish['id']);
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Збережено успішно!'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Зберегти'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _dishesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final List<Map<String, dynamic>> allDishes = snapshot.hasData ? snapshot.data! : [];
          if (allDishes.isEmpty) return const Center(child: Text('У меню поки немає страв'));

          final List<String> restaurantCategories = ['Всі', ...allDishes.map((d) => d['category']?.toString() ?? '').where((c) => c.isNotEmpty).toSet().toList()];

          if (!restaurantCategories.contains(_selectedCategory)) {
            _selectedCategory = 'Всі';
          }

          final filteredDishes = allDishes.where((d) {
            final matchesCat = _selectedCategory == 'Всі' || d['category'] == _selectedCategory;
            final matchesSearch = _searchQuery.isEmpty || d['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
            return matchesCat && matchesSearch;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Пошук страви (напр. Борщ)...', prefixIcon: const Icon(Icons.search, color: Colors.grey), filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),

              if (restaurantCategories.length > 1)
                Container(
                  height: 50, color: Colors.transparent,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: restaurantCategories.length,
                    itemBuilder: (context, index) {
                      final cat = restaurantCategories[index];
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected, onSelected: (_) => setState(() => _selectedCategory = cat),
                          backgroundColor: Colors.grey[200], selectedColor: Colors.red[800], checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey[400]!)),
                        ),
                      );
                    },
                  ),
                ),

              Expanded(
                child: filteredDishes.isEmpty
                    ? const Center(child: Text('За вашим запитом нічого не знайдено'))
                    : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, top: 4),
                  itemCount: filteredDishes.length,
                  itemBuilder: (context, index) {
                    final dish = filteredDishes[index];
                    return DishListItem(
                      dish: dish,
                      onEdit: () async {
                        final res = await SupabaseService.client.from('categories').select('*').order('name');
                        final cats = List<Map<String, dynamic>>.from(res as List);
                        if (mounted) _showEditDishDialog(dish: dish, globalCategoriesData: cats);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await SupabaseService.client.from('categories').select('*').order('name');
          final cats = List<Map<String, dynamic>>.from(res as List);
          if (mounted) _showEditDishDialog(globalCategoriesData: cats);
        },
        backgroundColor: Colors.red[800], foregroundColor: Colors.white,
        icon: const Icon(Icons.add), label: const Text('Додати страву'),
      ),
    );
  }
}

// ============================================================================
// ЕЛЕМЕНТ СПИСКУ СТРАВ
// ============================================================================
class DishListItem extends StatefulWidget {
  final Map<String, dynamic> dish;
  final VoidCallback onEdit;

  const DishListItem({super.key, required this.dish, required this.onEdit});

  @override
  State<DishListItem> createState() => _DishListItemState();
}

class _DishListItemState extends State<DishListItem> {
  late bool _isAvailable;

  @override
  void initState() {
    super.initState();
    _isAvailable = widget.dish['is_available'] ?? true;
  }

  @override
  void didUpdateWidget(covariant DishListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dish['is_available'] != widget.dish['is_available']) {
      _isAvailable = widget.dish['is_available'] ?? true;
    }
  }

  Future<void> _toggleAvailability(bool newValue) async {
    setState(() => _isAvailable = newValue);
    try {
      await SupabaseService.client.from('dishes').update({'is_available': newValue}).eq('id', widget.dish['id']);
    } catch (e) {
      if (mounted) {
        setState(() => _isAvailable = !newValue);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final sectionText = dish['section'] ?? 'Їжа';
    final isByWeight = dish['is_by_weight'] ?? false;
    final weightMeasure = dish['weight_measure'] ?? '';
    final priceText = isByWeight ? '${dish['price']} грн / $weightMeasure' : '${dish['price']} грн';

    // Перевіряємо, чи є модифікатори для відображення іконки
    final hasModifiers = (dish['removable_ingredients'] != null && (dish['removable_ingredients'] as List).isNotEmpty) ||
        (dish['addable_ingredients'] != null && (dish['addable_ingredients'] as List).isNotEmpty);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _isAvailable ? Colors.white : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isByWeight ? Colors.purple[200]! : Colors.grey[300]!, width: isByWeight ? 1.5 : 1)),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: _isAvailable ? 1.0 : 0.4,
            child: Image.network(dish['image'] ?? '', width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: 50, height: 50, color: Colors.grey[300])),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(dish['name'], style: TextStyle(fontWeight: FontWeight.bold, decoration: _isAvailable ? TextDecoration.none : TextDecoration.lineThrough, color: _isAvailable ? Colors.black : Colors.grey))),
            if (hasModifiers) const Icon(Icons.tune, size: 16, color: Colors.blueAccent), // Іконка налаштувань інгредієнтів
          ],
        ),
        subtitle: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4,
          children: [
            Text('$priceText • $sectionText -> ${dish['category']}'),
            if (isByWeight) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(4)), child: const Text('Вагова', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: _isAvailable, onChanged: _toggleAvailability, activeColor: Colors.green),
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: widget.onEdit),
          ],
        ),
      ),
    );
  }
=======
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/supabase_service.dart';

// ============================================================================
// УПРАВЛІННЯ МЕНЮ РЕСТОРАНУ
// ============================================================================
class RestaurantMenuManager extends StatefulWidget {
  final dynamic restaurantId;
  const RestaurantMenuManager({super.key, required this.restaurantId});

  @override
  State<RestaurantMenuManager> createState() => _RestaurantMenuManagerState();
}

class _RestaurantMenuManagerState extends State<RestaurantMenuManager> with AutomaticKeepAliveClientMixin {
  final List<String> _sections = ['Їжа', 'Безалкогольні напої', 'Алкогольні напої'];
  String _selectedCategory = 'Всі';
  String _searchQuery = '';
  late Stream<List<Map<String, dynamic>>> _dishesStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dishesStream = SupabaseService.client
        .from('dishes')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', widget.restaurantId)
        .order('name');
  }

  void _showEditDishDialog({Map<String, dynamic>? dish, required List<Map<String, dynamic>> globalCategoriesData}) {
    final isNew = dish == null;
    final nameCtrl = TextEditingController(text: dish?['name'] ?? '');
    final descCtrl = TextEditingController(text: dish?['description'] ?? '');
    final priceCtrl = TextEditingController(text: dish?['price']?.toString() ?? '');
    final imageCtrl = TextEditingController(text: dish?['image'] ?? '');

    bool isByWeight = dish?['is_by_weight'] ?? false;
    final weightMeasureCtrl = TextEditingController(text: dish?['weight_measure'] ?? '100 г');

    // --- ЗМІННІ ДЛЯ МОДИФІКАТОРІВ ---
    List<String> removableList = List<String>.from(dish?['removable_ingredients'] ?? []);
    List<Map<String, dynamic>> addableList = List<Map<String, dynamic>>.from(dish?['addable_ingredients'] ?? []);

    final removeInputCtrl = TextEditingController();
    final addNameCtrl = TextEditingController();
    final addPriceCtrl = TextEditingController();
    // --------------------------------

    String selectedSection = dish?['section'] ?? _sections.first;

    List<String> getFilteredCategories(String section) {
      return globalCategoriesData.where((c) => c['section'] == section).map((c) => c['name'].toString()).toList();
    }

    List<String> currentFilteredCats = getFilteredCategories(selectedSection);
    String selectedCat = dish?['category'] ?? (currentFilteredCats.isNotEmpty ? currentFilteredCats.first : '');

    if (selectedCat.isNotEmpty && !currentFilteredCats.contains(selectedCat)) {
      currentFilteredCats.add(selectedCat);
    }

    bool isAvailable = dish?['is_available'] ?? true;
    bool isUploadingImage = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(isNew ? 'Нова страва' : 'Редагувати страву'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                          if (image != null) {
                            setDialogState(() => isUploadingImage = true);
                            try {
                              final bytes = await image.readAsBytes();
                              final fileExt = image.name.split('.').last;
                              final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                              await SupabaseService.client.storage.from('dish_images').uploadBinary(fileName, bytes);
                              final publicUrl = SupabaseService.client.storage.from('dish_images').getPublicUrl(fileName);
                              setDialogState(() { imageCtrl.text = publicUrl; isUploadingImage = false; });
                            } catch (e) {
                              setDialogState(() => isUploadingImage = false);
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
                            }
                          }
                        },
                        child: Container(
                          height: 150, width: double.infinity,
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), image: imageCtrl.text.isNotEmpty ? DecorationImage(image: NetworkImage(imageCtrl.text), fit: BoxFit.contain) : null, border: Border.all(color: Colors.grey[400]!)),
                          child: isUploadingImage ? const Center(child: CircularProgressIndicator()) : (imageCtrl.text.isEmpty ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40, color: Colors.grey), SizedBox(height: 8), Text('Фото', style: TextStyle(color: Colors.grey))]) : Container(alignment: Alignment.bottomRight, padding: const EdgeInsets.all(8), child: const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.edit, size: 20, color: Colors.black)))),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Назва')),
                      TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Склад / Опис'), maxLines: 2),
                      TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Ціна (грн)'), keyboardType: TextInputType.number),
                      const SizedBox(height: 16),

                      Container(
                        decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple[200]!)),
                        child: Column(
                          children: [
                            SwitchListTile(title: const Text('Продається на вагу', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)), subtitle: const Text('Ціна залежатиме від ваги', style: TextStyle(fontSize: 12)), value: isByWeight, onChanged: (val) => setDialogState(() => isByWeight = val), activeColor: Colors.purple),
                            if (isByWeight) Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16), child: TextField(controller: weightMeasureCtrl, decoration: const InputDecoration(labelText: 'Одиниця виміру (напр. 100 г)', filled: true, fillColor: Colors.white))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ========================================================
                      // БЛОК: МОДИФІКАТОРИ ІНГРЕДІЄНТІВ
                      // ========================================================
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent), borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          title: const Text('🍔 Модифікатори інгредієнтів', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            // 1. ЩО МОЖНА ПРИБРАТИ
                            const Align(alignment: Alignment.centerLeft, child: Text('Можна прибрати (безкоштовно):', style: TextStyle(fontWeight: FontWeight.bold))),
                            Row(
                              children: [
                                Expanded(child: TextField(controller: removeInputCtrl, decoration: const InputDecoration(hintText: 'напр. Без цибулі', isDense: true))),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.redAccent),
                                  onPressed: () {
                                    if (removeInputCtrl.text.isNotEmpty) {
                                      setDialogState(() { removableList.add(removeInputCtrl.text.trim()); removeInputCtrl.clear(); });
                                    }
                                  },
                                )
                              ],
                            ),
                            if (removableList.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: removableList.map((item) => Chip(
                                  label: Text(item, style: const TextStyle(fontSize: 12)),
                                  onDeleted: () => setDialogState(() => removableList.remove(item)),
                                  backgroundColor: Colors.red[50], deleteIconColor: Colors.red,
                                )).toList(),
                              ),

                            const Divider(height: 24),

                            // 2. ЩО МОЖНА ДОДАТИ
                            const Align(alignment: Alignment.centerLeft, child: Text('Можна додати (за доплату):', style: TextStyle(fontWeight: FontWeight.bold))),
                            Row(
                              children: [
                                Expanded(flex: 2, child: TextField(controller: addNameCtrl, decoration: const InputDecoration(hintText: 'напр. Сир', isDense: true))),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: TextField(controller: addPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Ціна', isDense: true))),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.green),
                                  onPressed: () {
                                    if (addNameCtrl.text.isNotEmpty && addPriceCtrl.text.isNotEmpty) {
                                      setDialogState(() {
                                        addableList.add({ 'name': addNameCtrl.text.trim(), 'price': double.tryParse(addPriceCtrl.text.trim()) ?? 0 });
                                        addNameCtrl.clear(); addPriceCtrl.clear();
                                      });
                                    }
                                  },
                                )
                              ],
                            ),
                            if (addableList.isNotEmpty)
                              Column(
                                  children: addableList.map((item) => Card(
                                      color: Colors.green[50], margin: const EdgeInsets.symmetric(vertical: 4),
                                      child: ListTile(
                                        dense: true,
                                        title: Text(item['name']), trailing: Row(mainAxisSize: MainAxisSize.min, children: [ Text('+${item['price']} грн', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), onPressed: () => setDialogState(() => addableList.remove(item))) ]),
                                      )
                                  )).toList()
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ========================================================

                      DropdownButtonFormField<String>(
                        value: _sections.contains(selectedSection) ? selectedSection : _sections.first,
                        decoration: const InputDecoration(labelText: 'Тип меню (Розділ)'),
                        items: _sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) { setDialogState(() { selectedSection = val!; currentFilteredCats = getFilteredCategories(selectedSection); selectedCat = currentFilteredCats.isNotEmpty ? currentFilteredCats.first : ''; }); },
                      ),
                      const SizedBox(height: 10),

                      if (currentFilteredCats.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: selectedCat.isEmpty ? null : selectedCat, decoration: const InputDecoration(labelText: 'Категорія'),
                          items: currentFilteredCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) => setDialogState(() => selectedCat = val!),
                        )
                      else
                        Container(padding: const EdgeInsets.all(8), color: Colors.red[50], child: Text('У розділі "$selectedSection" ще немає категорій.', style: const TextStyle(color: Colors.red, fontSize: 12))),

                      const SizedBox(height: 10),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Доступно'), value: isAvailable, onChanged: (val) => setDialogState(() => isAvailable = val), activeColor: Colors.green),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати', style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty || selectedCat.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заповніть назву, ціну та категорію!')));
                        return;
                      }

                      final dishData = {
                        'restaurant_id': widget.restaurantId,
                        'name': nameCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'price': double.tryParse(priceCtrl.text.trim()) ?? 0.0,
                        'section': selectedSection,
                        'category': selectedCat,
                        'image': imageCtrl.text.trim(),
                        'is_available': isAvailable,
                        'is_by_weight': isByWeight,
                        'weight_measure': isByWeight ? weightMeasureCtrl.text.trim() : null,
                        // --- ЗБЕРІГАЄМО МОДИФІКАТОРИ В БАЗУ ---
                        'removable_ingredients': removableList,
                        'addable_ingredients': addableList,
                        // -------------------------------------
                      };

                      try {
                        if (isNew) {
                          await SupabaseService.client.from('dishes').insert(dishData);
                        } else {
                          await SupabaseService.client.from('dishes').update(dishData).eq('id', dish['id']);
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Збережено успішно!'), backgroundColor: Colors.green));
                        }
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Зберегти'),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _dishesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final List<Map<String, dynamic>> allDishes = snapshot.hasData ? snapshot.data! : [];
          if (allDishes.isEmpty) return const Center(child: Text('У меню поки немає страв'));

          final List<String> restaurantCategories = ['Всі', ...allDishes.map((d) => d['category']?.toString() ?? '').where((c) => c.isNotEmpty).toSet().toList()];

          if (!restaurantCategories.contains(_selectedCategory)) {
            _selectedCategory = 'Всі';
          }

          final filteredDishes = allDishes.where((d) {
            final matchesCat = _selectedCategory == 'Всі' || d['category'] == _selectedCategory;
            final matchesSearch = _searchQuery.isEmpty || d['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
            return matchesCat && matchesSearch;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Пошук страви (напр. Борщ)...', prefixIcon: const Icon(Icons.search, color: Colors.grey), filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),

              if (restaurantCategories.length > 1)
                Container(
                  height: 50, color: Colors.transparent,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: restaurantCategories.length,
                    itemBuilder: (context, index) {
                      final cat = restaurantCategories[index];
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(cat, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected, onSelected: (_) => setState(() => _selectedCategory = cat),
                          backgroundColor: Colors.grey[200], selectedColor: Colors.red[800], checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey[400]!)),
                        ),
                      );
                    },
                  ),
                ),

              Expanded(
                child: filteredDishes.isEmpty
                    ? const Center(child: Text('За вашим запитом нічого не знайдено'))
                    : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, top: 4),
                  itemCount: filteredDishes.length,
                  itemBuilder: (context, index) {
                    final dish = filteredDishes[index];
                    return DishListItem(
                      dish: dish,
                      onEdit: () async {
                        final res = await SupabaseService.client.from('categories').select('*').order('name');
                        final cats = List<Map<String, dynamic>>.from(res as List);
                        if (mounted) _showEditDishDialog(dish: dish, globalCategoriesData: cats);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await SupabaseService.client.from('categories').select('*').order('name');
          final cats = List<Map<String, dynamic>>.from(res as List);
          if (mounted) _showEditDishDialog(globalCategoriesData: cats);
        },
        backgroundColor: Colors.red[800], foregroundColor: Colors.white,
        icon: const Icon(Icons.add), label: const Text('Додати страву'),
      ),
    );
  }
}

// ============================================================================
// ЕЛЕМЕНТ СПИСКУ СТРАВ
// ============================================================================
class DishListItem extends StatefulWidget {
  final Map<String, dynamic> dish;
  final VoidCallback onEdit;

  const DishListItem({super.key, required this.dish, required this.onEdit});

  @override
  State<DishListItem> createState() => _DishListItemState();
}

class _DishListItemState extends State<DishListItem> {
  late bool _isAvailable;

  @override
  void initState() {
    super.initState();
    _isAvailable = widget.dish['is_available'] ?? true;
  }

  @override
  void didUpdateWidget(covariant DishListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dish['is_available'] != widget.dish['is_available']) {
      _isAvailable = widget.dish['is_available'] ?? true;
    }
  }

  Future<void> _toggleAvailability(bool newValue) async {
    setState(() => _isAvailable = newValue);
    try {
      await SupabaseService.client.from('dishes').update({'is_available': newValue}).eq('id', widget.dish['id']);
    } catch (e) {
      if (mounted) {
        setState(() => _isAvailable = !newValue);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final sectionText = dish['section'] ?? 'Їжа';
    final isByWeight = dish['is_by_weight'] ?? false;
    final weightMeasure = dish['weight_measure'] ?? '';
    final priceText = isByWeight ? '${dish['price']} грн / $weightMeasure' : '${dish['price']} грн';

    // Перевіряємо, чи є модифікатори для відображення іконки
    final hasModifiers = (dish['removable_ingredients'] != null && (dish['removable_ingredients'] as List).isNotEmpty) ||
        (dish['addable_ingredients'] != null && (dish['addable_ingredients'] as List).isNotEmpty);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _isAvailable ? Colors.white : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isByWeight ? Colors.purple[200]! : Colors.grey[300]!, width: isByWeight ? 1.5 : 1)),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: _isAvailable ? 1.0 : 0.4,
            child: Image.network(dish['image'] ?? '', width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: 50, height: 50, color: Colors.grey[300])),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(dish['name'], style: TextStyle(fontWeight: FontWeight.bold, decoration: _isAvailable ? TextDecoration.none : TextDecoration.lineThrough, color: _isAvailable ? Colors.black : Colors.grey))),
            if (hasModifiers) const Icon(Icons.tune, size: 16, color: Colors.blueAccent), // Іконка налаштувань інгредієнтів
          ],
        ),
        subtitle: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4,
          children: [
            Text('$priceText • $sectionText -> ${dish['category']}'),
            if (isByWeight) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(4)), child: const Text('Вагова', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: _isAvailable, onChanged: _toggleAvailability, activeColor: Colors.green),
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: widget.onEdit),
          ],
        ),
      ),
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}