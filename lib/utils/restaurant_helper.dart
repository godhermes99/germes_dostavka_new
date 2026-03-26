import 'package:flutter/material.dart';

// Глобальна функція перевірки графіка роботи
bool checkIsRestaurantOpen(Map<String, dynamic> restaurant) {
  bool isManualOpen = restaurant['is_open'] ?? true;
  if (!isManualOpen) return false;

  String openStr = restaurant['open_time'] ?? '10:00';
  String closeStr = restaurant['close_time'] ?? '22:00';

  try {
    DateTime now = DateTime.now();
    int currentMinutes = now.hour * 60 + now.minute;

    int openMinutes = int.parse(openStr.split(':')[0]) * 60 + int.parse(openStr.split(':')[1]);
    int closeMinutes = int.parse(closeStr.split(':')[0]) * 60 + int.parse(closeStr.split(':')[1]);

    if (closeMinutes < openMinutes) {
      return currentMinutes >= openMinutes || currentMinutes <= closeMinutes;
    } else {
      return currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
    }
  } catch (e) {
    debugPrint('Помилка парсингу часу: $e');
    return true;
  }
}