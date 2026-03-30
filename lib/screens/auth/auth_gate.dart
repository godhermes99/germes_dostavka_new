<<<<<<< HEAD
import 'package:flutter/material.dart';
import '../../core/supabase_service.dart';
import '../main_navigator.dart';
import 'phone_login_screen.dart';
import 'complete_profile_screen.dart';

import '../../restaurant/restaurant_dashboard_screen.dart';
import '../courier_dashboard_screen.dart';
import '../admin_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Map<String, dynamic>> _getUserData() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return {'status': 'unauthorized'};

    final profile = await SupabaseService.client
        .from('profiles')
    // ДОДАНО: Додали city у список полів, які витягуємо з бази
        .select('full_name, address, city, role, managed_restaurant_id')
        .eq('user_id', user.id)
        .maybeSingle();

    final fullName = (profile?['full_name'] as String?)?.trim();
    final address = (profile?['address'] as String?)?.trim();
    final city = (profile?['city'] as String?)?.trim(); // ДОДАНО: Змінна міста
    final role = profile?['role'] as String? ?? 'client';
    final managedRestaurantId = profile?['managed_restaurant_id'];

    // 1. ПЕРЕВІРКА НА АДМІНА
    if (role == 'admin') {
      return {'status': 'is_admin'};
    }

    // 2. Перевірка заповненості профілю для всіх інших
    // ДОДАНО: Тепер додаток відправить на реєстрацію, якщо немає Імені, Адреси АБО Міста
    if ((fullName == null || fullName.isEmpty) ||
        (address == null || address.isEmpty) ||
        (city == null || city.isEmpty)) {
      return {'status': 'needs_profile'};
    }

    // 3. Перевірка на менеджера ресторану
    if (role == 'restaurant' && managedRestaurantId != null) {
      return {'status': 'is_restaurant', 'restaurant_id': managedRestaurantId};
    }

    // 4. Перевірка на кур'єра
    if (role == 'courier') {
      return {'status': 'is_courier'};
    }

    // 5. За замовчуванням - звичайний клієнт
    return {'status': 'is_client'};
  }

  @override
  Widget build(BuildContext context) {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) return const PhoneLoginScreen();

    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!;

        switch (data['status']) {
          case 'needs_profile':
            return const CompleteProfileScreen();
          case 'is_admin':
            return const AdminDashboardScreen();
          case 'is_restaurant':
            return RestaurantDashboardScreen(restaurantId: data['restaurant_id']);
          case 'is_courier':
            return const CourierDashboardScreen();
          case 'is_client':
          default:
            return const MainNavigator();
        }
      },
    );
  }
=======
import 'package:flutter/material.dart';
import '../../core/supabase_service.dart';
import '../main_navigator.dart';
import 'phone_login_screen.dart';
import 'complete_profile_screen.dart';

import '../../restaurant/restaurant_dashboard_screen.dart';
import '../courier_dashboard_screen.dart';
import '../admin_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Map<String, dynamic>> _getUserData() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return {'status': 'unauthorized'};

    final profile = await SupabaseService.client
        .from('profiles')
    // ДОДАНО: Додали city у список полів, які витягуємо з бази
        .select('full_name, address, city, role, managed_restaurant_id')
        .eq('user_id', user.id)
        .maybeSingle();

    final fullName = (profile?['full_name'] as String?)?.trim();
    final address = (profile?['address'] as String?)?.trim();
    final city = (profile?['city'] as String?)?.trim(); // ДОДАНО: Змінна міста
    final role = profile?['role'] as String? ?? 'client';
    final managedRestaurantId = profile?['managed_restaurant_id'];

    // 1. ПЕРЕВІРКА НА АДМІНА
    if (role == 'admin') {
      return {'status': 'is_admin'};
    }

    // 2. Перевірка заповненості профілю для всіх інших
    // ДОДАНО: Тепер додаток відправить на реєстрацію, якщо немає Імені, Адреси АБО Міста
    if ((fullName == null || fullName.isEmpty) ||
        (address == null || address.isEmpty) ||
        (city == null || city.isEmpty)) {
      return {'status': 'needs_profile'};
    }

    // 3. Перевірка на менеджера ресторану
    if (role == 'restaurant' && managedRestaurantId != null) {
      return {'status': 'is_restaurant', 'restaurant_id': managedRestaurantId};
    }

    // 4. Перевірка на кур'єра
    if (role == 'courier') {
      return {'status': 'is_courier'};
    }

    // 5. За замовчуванням - звичайний клієнт
    return {'status': 'is_client'};
  }

  @override
  Widget build(BuildContext context) {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) return const PhoneLoginScreen();

    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!;

        switch (data['status']) {
          case 'needs_profile':
            return const CompleteProfileScreen();
          case 'is_admin':
            return const AdminDashboardScreen();
          case 'is_restaurant':
            return RestaurantDashboardScreen(restaurantId: data['restaurant_id']);
          case 'is_courier':
            return const CourierDashboardScreen();
          case 'is_client':
          default:
            return const MainNavigator();
        }
      },
    );
  }
>>>>>>> 467667475cbaf79afed5ea350d290cd705acbd73
}