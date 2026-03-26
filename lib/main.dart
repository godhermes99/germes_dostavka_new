import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// === FIREBASE ІМПОРТИ ===
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'dart:io';
// === НАШІ ІМПОРТИ ===
import 'core/supabase_service.dart';
import 'providers/cart_provider.dart';
import 'screens/onboarding/splash_screen.dart';
import 'providers/theme_provider.dart';
import 'core/notification_service.dart'; // 🔥 ДОДАНО ІМПОРТ

// 1. ФУНКЦІЯ ДЛЯ ОБРОБКИ ПУШІВ У ФОНІ
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Отримано фонове повідомлення: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. ІНІЦІАЛІЗАЦІЯ FIREBASE
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. ПРИВ'ЯЗКА ФОНОВОГО ОБРОБНИКА FIREBASE
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 4. ЗАПИТ ДОЗВОЛУ НА СПОВІЩЕННЯ
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // 🔥 5. НАЛАШТУВАННЯ ДЛЯ ВІДКРИТОГО ДОДАТКА (Щоб пуші вискакували завжди)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true, // Показувати банер
    badge: true,
    sound: true, // Грати звук!
  );

  // 6. Ініціалізація нашої бази даних
  await SupabaseService.init();

  // 7. Ініціалізація локальних пушів
  await NotificationService().init();

  // === СТВОРЕННЯ ГУЧНОГО КАНАЛУ ДЛЯ ANDROID ===
  if (Platform.isAndroid) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'hermes_loud_channel', // 🔥 ОСЬ НАЗВА ТВОГО КАНАЛУ
      'Гучні сповіщення',
      description: 'Канал для нових замовлень (максимальна гучність)',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('loud_alarm'),
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  // ============================================

  // 🔥 8. СЛУХАЄМО ПУШІ, КОЛИ ДОДАТОК ВІДКРИТИЙ (Foreground)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("Отримано пуш у відкритому додатку: ${message.notification?.title}");
    if (message.notification != null) {
      // Примусово показуємо локальне сповіщення (щоб звук 100% зіграв)
      NotificationService().showNotification(
        id: message.hashCode,
        title: message.notification!.title ?? '',
        body: message.notification!.body ?? '',
      );
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Гермес Доставка',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,

      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF005BBB),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.light,
          seedColor: const Color(0xFF005BBB),
          secondary: const Color(0xFFFFCD00),
        ),
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.light().textTheme),
        useMaterial3: true,
      ),

      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF005BBB),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF005BBB),
          secondary: const Color(0xFFFFCD00),
        ),
        textTheme: GoogleFonts.montserratTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('uk', 'UA')],
      locale: const Locale('uk', 'UA'),

      home: const SplashScreen(),
    );
  }
}