<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // За замовчуванням ставимо системну тему (залежить від налаштувань телефону)
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  // Завантажуємо збережену тему при запуску
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode');

    if (savedTheme == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  // Змінюємо тему і зберігаємо вибір
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.light) {
      await prefs.setString('themeMode', 'light');
    } else if (mode == ThemeMode.dark) {
      await prefs.setString('themeMode', 'dark');
    } else {
      await prefs.remove('themeMode'); // Якщо системна - просто видаляємо запис
    }
  }
=======
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // За замовчуванням ставимо системну тему (залежить від налаштувань телефону)
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  // Завантажуємо збережену тему при запуску
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('themeMode');

    if (savedTheme == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  // Змінюємо тему і зберігаємо вибір
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (mode == ThemeMode.light) {
      await prefs.setString('themeMode', 'light');
    } else if (mode == ThemeMode.dark) {
      await prefs.setString('themeMode', 'dark');
    } else {
      await prefs.remove('themeMode'); // Якщо системна - просто видаляємо запис
    }
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}