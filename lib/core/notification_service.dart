import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Ініціалізуємо часові пояси для відкладених пушів
    tz.initializeTimeZones();

    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true, 
    );
    
    const InitializationSettings initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsIOS,
    );
    
    // Додаємо обробник кліку по сповіщенню!
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Коли ми зробимо екран відгуків, тут ми будемо зчитувати response.payload
        // і перекидати користувача на потрібний екран. Поки що просто клікабельно.
      },
    );
  }

  // Миттєве сповіщення
  Future<void> showNotification({required int id, required String title, required String body}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'order_status_channel_v2', 
      'Оновлення замовлень', 
      channelDescription: 'Сповіщення про зміну статусу вашого замовлення',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true, presentAlert: true, presentBadge: true,
    );
    
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _notificationsPlugin.show(id, title, body, platformDetails);
  }

  // ВІДКЛАДЕНЕ СПОВІЩЕННЯ (Нова функція)
  Future<void> scheduleNotification({
    required int id, 
    required String title, 
    required String body, 
    required int delayMinutes,
    String? payload, // Для обробки кліку
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'review_channel_v1', 
      'Нагадування про відгук', 
      channelDescription: 'Прохання залишити відгук після їжі',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.now(tz.local).add(Duration(minutes: delayMinutes)), // Відлік часу
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // Точно в строк
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload, // Передаємо дані для кліку
    );
  }
}