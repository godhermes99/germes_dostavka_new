<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CartProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _items = [];
  dynamic _currentRestaurantId;

  CartProvider() {
    _loadCart();
  }

  List<Map<String, dynamic>> get items => _items;
  dynamic get restaurantId => _currentRestaurantId;

  double get total => _items.fold(0.0, (sum, item) {
    final price = (item['price'] as num).toDouble();
    final quantity = (item['quantity'] as int);
    return sum + price * quantity;
  });

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String cartJson = json.encode(_items);
    await prefs.setString('saved_cart_items', cartJson);

    if (_currentRestaurantId != null) {
      await prefs.setString('saved_restaurant_id', _currentRestaurantId.toString());
    } else {
      await prefs.remove('saved_restaurant_id');
    }
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartJson = prefs.getString('saved_cart_items');
    final String? savedRestId = prefs.getString('saved_restaurant_id');

    if (cartJson != null) {
      final List<dynamic> decodedData = json.decode(cartJson);
      _items.clear();
      _items.addAll(decodedData.map((item) => Map<String, dynamic>.from(item)));
    }

    if (savedRestId != null) {
      _currentRestaurantId = savedRestId;
    }

    notifyListeners();
  }

  // ==========================================================================
  // ГЕНЕРАТОР УНІКАЛЬНОГО КЛЮЧА ДЛЯ МОДИФІКОВАНИХ СТРАВ
  // ==========================================================================
  String _generateCartKey(Map<String, dynamic> dish) {
    final String id = dish['id'].toString();

    // Сортуємо видалені інгредієнти, щоб порядок не впливав на результат
    List<String> removed = [];
    if (dish['removed_ingredients'] != null) {
      removed = List<String>.from(dish['removed_ingredients']);
      removed.sort();
    }

    // Сортуємо додані інгредієнти
    List<String> added = [];
    if (dish['added_ingredients'] != null) {
      added = List<Map<String, dynamic>>.from(dish['added_ingredients'])
          .map((e) => e['name'].toString())
          .toList();
      added.sort();
    }

    // Створюємо унікальний рядок-ідентифікатор: "id_rem_цибуля_add_сир"
    return '${id}_rem_${removed.join('|')}_add_${added.join('|')}';
  }
  // ==========================================================================

  bool addItem(Map<String, dynamic> dish) {
    final incomingRestId = dish['restaurant_id']?.toString();

    if (incomingRestId == null) return false;

    if (_items.isEmpty) {
      _currentRestaurantId = incomingRestId;
    } else if (_currentRestaurantId.toString() != incomingRestId) {
      return false; // Конфлікт ресторанів
    }

    // 1. Генеруємо унікальний ключ для цієї конкретної модифікації
    final String cartKey = _generateCartKey(dish);

    // 2. Шукаємо в кошику страву САМЕ З ТАКИМ КЛЮЧЕМ
    final index = _items.indexWhere((i) => i['cart_key'] == cartKey);

    if (index != -1) {
      // Якщо така сама модифікація вже є — просто збільшуємо кількість
      _items[index]['quantity'] = (_items[index]['quantity'] as int) + 1;
    } else {
      // Якщо це нова страва або нова модифікація — додаємо як новий рядок
      final newItem = Map<String, dynamic>.from(dish);
      newItem['quantity'] = 1;
      newItem['cart_key'] = cartKey; // Зберігаємо ключ у саму страву!
      _items.add(newItem);
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  // ТЕПЕР ВИДАЛЯЄМО  ЗА 'id', ЗА 'cart_key'
  void removeItem(String key) {
    // Шукаємо або за унікальним ключем, або за старим ID
    _items.removeWhere((item) => item['cart_key']?.toString() == key || item['id'].toString() == key);

    if (_items.isEmpty) {
      _currentRestaurantId = null;
    }

    _saveCart();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _currentRestaurantId = null;
    _saveCart();
    notifyListeners();
  }
=======
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CartProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _items = [];
  dynamic _currentRestaurantId;

  CartProvider() {
    _loadCart();
  }

  List<Map<String, dynamic>> get items => _items;
  dynamic get restaurantId => _currentRestaurantId;

  double get total => _items.fold(0.0, (sum, item) {
    final price = (item['price'] as num).toDouble();
    final quantity = (item['quantity'] as int);
    return sum + price * quantity;
  });

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String cartJson = json.encode(_items);
    await prefs.setString('saved_cart_items', cartJson);

    if (_currentRestaurantId != null) {
      await prefs.setString('saved_restaurant_id', _currentRestaurantId.toString());
    } else {
      await prefs.remove('saved_restaurant_id');
    }
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartJson = prefs.getString('saved_cart_items');
    final String? savedRestId = prefs.getString('saved_restaurant_id');

    if (cartJson != null) {
      final List<dynamic> decodedData = json.decode(cartJson);
      _items.clear();
      _items.addAll(decodedData.map((item) => Map<String, dynamic>.from(item)));
    }

    if (savedRestId != null) {
      _currentRestaurantId = savedRestId;
    }

    notifyListeners();
  }

  // ==========================================================================
  // ГЕНЕРАТОР УНІКАЛЬНОГО КЛЮЧА ДЛЯ МОДИФІКОВАНИХ СТРАВ
  // ==========================================================================
  String _generateCartKey(Map<String, dynamic> dish) {
    final String id = dish['id'].toString();

    // Сортуємо видалені інгредієнти, щоб порядок не впливав на результат
    List<String> removed = [];
    if (dish['removed_ingredients'] != null) {
      removed = List<String>.from(dish['removed_ingredients']);
      removed.sort();
    }

    // Сортуємо додані інгредієнти
    List<String> added = [];
    if (dish['added_ingredients'] != null) {
      added = List<Map<String, dynamic>>.from(dish['added_ingredients'])
          .map((e) => e['name'].toString())
          .toList();
      added.sort();
    }

    // Створюємо унікальний рядок-ідентифікатор: "id_rem_цибуля_add_сир"
    return '${id}_rem_${removed.join('|')}_add_${added.join('|')}';
  }
  // ==========================================================================

  bool addItem(Map<String, dynamic> dish) {
    final incomingRestId = dish['restaurant_id']?.toString();

    if (incomingRestId == null) return false;

    if (_items.isEmpty) {
      _currentRestaurantId = incomingRestId;
    } else if (_currentRestaurantId.toString() != incomingRestId) {
      return false; // Конфлікт ресторанів
    }

    // 1. Генеруємо унікальний ключ для цієї конкретної модифікації
    final String cartKey = _generateCartKey(dish);

    // 2. Шукаємо в кошику страву САМЕ З ТАКИМ КЛЮЧЕМ
    final index = _items.indexWhere((i) => i['cart_key'] == cartKey);

    if (index != -1) {
      // Якщо така сама модифікація вже є — просто збільшуємо кількість
      _items[index]['quantity'] = (_items[index]['quantity'] as int) + 1;
    } else {
      // Якщо це нова страва або нова модифікація — додаємо як новий рядок
      final newItem = Map<String, dynamic>.from(dish);
      newItem['quantity'] = 1;
      newItem['cart_key'] = cartKey; // Зберігаємо ключ у саму страву!
      _items.add(newItem);
    }

    _saveCart();
    notifyListeners();
    return true;
  }

  // ТЕПЕР ВИДАЛЯЄМО  ЗА 'id', ЗА 'cart_key'
  void removeItem(String key) {
    // Шукаємо або за унікальним ключем, або за старим ID
    _items.removeWhere((item) => item['cart_key']?.toString() == key || item['id'].toString() == key);

    if (_items.isEmpty) {
      _currentRestaurantId = null;
    }

    _saveCart();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _currentRestaurantId = null;
    _saveCart();
    notifyListeners();
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}