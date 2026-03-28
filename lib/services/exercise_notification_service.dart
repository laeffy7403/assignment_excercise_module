import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final status = await Permission.notification.request();
    if (status.isDenied) {
      print('Notification permission denied');
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // v21 uses 'settings' as named parameter
    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _initialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
  }

  Future<void> notifyStepGoalReached(int steps, int goal) async {
    await _showNotification(
      id: 1,
      title: '🎉 Step Goal Achieved!',
      body: 'Congratulations! You\'ve reached your goal of $goal steps!',
      payload: 'step_goal_$steps',
    );
  }

  Future<void> notifyDistanceGoalReached(double distance, double goal) async {
    await _showNotification(
      id: 2,
      title: '🏃 Distance Goal Achieved!',
      body: 'Great job! You\'ve covered ${goal.toStringAsFixed(1)} km!',
      payload: 'distance_goal_$distance',
    );
  }

  Future<void> notifyTimeGoalReached(int minutes) async {
    await _showNotification(
      id: 3,
      title: '⏱️ Time Goal Achieved!',
      body: 'You\'ve been active for $minutes minutes!',
      payload: 'time_goal_$minutes',
    );
  }

  Future<void> notifyCalorieGoalReached(int calories, int goal) async {
    await _showNotification(
      id: 4,
      title: '🔥 Calorie Goal Achieved!',
      body: 'Amazing! You\'ve burned $goal calories!',
      payload: 'calorie_goal_$calories',
    );
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'fitness_goals',
      'Fitness Goals',
      channelDescription: 'Notifications for achieved fitness goals',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // v21 uses named parameters instead of positional
    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> showProgressNotification({
    required int steps,
    required double distance,
    required int duration,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'workout_progress',
      'Workout Progress',
      channelDescription: 'Shows current workout progress',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: 999,
      title: 'Workout in Progress',
      body: '$steps steps • ${distance.toStringAsFixed(2)} km • $duration min',
      notificationDetails: details,
    );
  }

  Future<void> cancelProgressNotification() async {
    // v21 uses named parameter
    await _notifications.cancel(id: 999);
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}