import 'package:flutter/material.dart';
import 'dart:convert';

enum ExerciseType {
  walking,
  running,
  jogging,
}

extension ExerciseTypeExtension on ExerciseType {
  String get displayName {
    switch (this) {
      case ExerciseType.walking:
        return 'Walking';
      case ExerciseType.running:
        return 'Running';
      case ExerciseType.jogging:
        return 'Jogging';
    }
  }

  Color get color {
    switch (this) {
      case ExerciseType.walking:
        return const Color(0xFFFFB6C1); // Pink
      case ExerciseType.running:
        return const Color(0xFFB4E7B4); // Green
      case ExerciseType.jogging:
        return const Color(0xFFC4B5FD); // Purple
    }
  }

  /// Soft tinted background for exercise cards, classified by type.
  Color get cardBackground {
    switch (this) {
      case ExerciseType.walking:
        return const Color(0xFFFFF0F3); // soft rose
      case ExerciseType.running:
        return const Color(0xFFEDF7ED); // soft mint
      case ExerciseType.jogging:
        return const Color(0xFFF3F0FF); // soft lavender
    }
  }

  /// Accent / border color for the card's left indicator strip.
  Color get cardAccent {
    switch (this) {
      case ExerciseType.walking:
        return const Color(0xFFE91E63); // deep rose
      case ExerciseType.running:
        return const Color(0xFF43A047); // deep green
      case ExerciseType.jogging:
        return const Color(0xFF7C6FDC); // deep purple
    }
  }

  IconData get icon {
    switch (this) {
      case ExerciseType.walking:
        return Icons.directions_walk;
      case ExerciseType.running:
        return Icons.directions_run;
      case ExerciseType.jogging:
        return Icons.run_circle;
    }
  }
}

class Exercise {
  String? id;
  String title;
  ExerciseType type;
  DateTime startTime;
  int durationMinutes;
  double? distanceKm;
  int? energyExpended;
  int? steps;
  String? notes;
  List<Map<String, double>>? routePoints;
  DateTime createdAt;

  // Goal fields
  int? stepGoal;
  double? distanceGoal;
  int? timeGoal;

  /// True when this entry was created by the auto-detection system.
  /// Auto-detected entries are read-only: steps, distance, and duration
  /// are locked and cannot be edited after saving.
  bool isAutoDetected;

  Exercise({
    this.id,
    required this.title,
    required this.type,
    required this.startTime,
    required this.durationMinutes,
    this.distanceKm,
    this.energyExpended,
    this.steps,
    this.notes,
    this.routePoints,
    DateTime? createdAt,
    this.stepGoal,
    this.distanceGoal,
    this.timeGoal,
    this.isAutoDetected = false,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (title.isEmpty) {
      title = _generateDefaultTitle();
    }
  }

  String _generateDefaultTitle() {
    final timeOfDay = startTime.hour;
    String period;
    if (timeOfDay < 12) {
      period = 'Morning';
    } else if (timeOfDay < 17) {
      period = 'Afternoon';
    } else if (timeOfDay < 21) {
      period = 'Evening';
    } else {
      period = 'Night';
    }
    return '$period ${type.displayName}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type.index,
      'startTime': startTime.toIso8601String(),
      'durationMinutes': durationMinutes,
      'distanceKm': distanceKm,
      'energyExpended': energyExpended,
      'steps': steps,
      'notes': notes,
      'routePoints': routePoints != null ? jsonEncode(routePoints) : null,
      'createdAt': createdAt.toIso8601String(),
      'stepGoal': stepGoal,
      'distanceGoal': distanceGoal,
      'timeGoal': timeGoal,
      // Store as integer (SQLite has no boolean)
      'isAutoDetected': isAutoDetected ? 1 : 0,
    };
  }

  factory Exercise.fromJson(Map<String, dynamic> json) {
    List<Map<String, double>>? parseRoutePoints(dynamic routeData) {
      if (routeData == null) return null;
      if (routeData is String) {
        try {
          final decoded = jsonDecode(routeData) as List;
          return decoded
              .map((point) => Map<String, double>.from(point as Map))
              .toList();
        } catch (e) {
          return null;
        }
      }
      return null;
    }

    return Exercise(
      id: json['id'],
      title: json['title'],
      type: ExerciseType.values[json['type']],
      startTime: DateTime.parse(json['startTime']),
      durationMinutes: json['durationMinutes'],
      distanceKm: json['distanceKm']?.toDouble(),
      energyExpended: json['energyExpended'],
      steps: json['steps'],
      notes: json['notes'],
      routePoints: parseRoutePoints(json['routePoints']),
      createdAt: DateTime.parse(json['createdAt']),
      stepGoal: json['stepGoal'],
      distanceGoal: json['distanceGoal']?.toDouble(),
      timeGoal: json['timeGoal'],
      isAutoDetected: (json['isAutoDetected'] ?? 0) == 1,
    );
  }

  Exercise copyWith({
    String? id,
    String? title,
    ExerciseType? type,
    DateTime? startTime,
    int? durationMinutes,
    double? distanceKm,
    int? energyExpended,
    int? steps,
    String? notes,
    List<Map<String, double>>? routePoints,
    DateTime? createdAt,
    int? stepGoal,
    double? distanceGoal,
    int? timeGoal,
    bool? isAutoDetected,
  }) {
    return Exercise(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      distanceKm: distanceKm ?? this.distanceKm,
      energyExpended: energyExpended ?? this.energyExpended,
      steps: steps ?? this.steps,
      notes: notes ?? this.notes,
      routePoints: routePoints ?? this.routePoints,
      createdAt: createdAt ?? this.createdAt,
      stepGoal: stepGoal ?? this.stepGoal,
      distanceGoal: distanceGoal ?? this.distanceGoal,
      timeGoal: timeGoal ?? this.timeGoal,
      isAutoDetected: isAutoDetected ?? this.isAutoDetected,
    );
  }

  String get formattedDistance {
    if (distanceKm == null) return '';
    return '${distanceKm!.toStringAsFixed(2)} km';
  }

  String get formattedDuration => '$durationMinutes min';

  String get formattedSteps {
    if (steps == null) return '';
    return '${steps!.toStringAsFixed(0)} steps';
  }

  String get formattedCalories {
    if (energyExpended == null) return '';
    return '$energyExpended cal';
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final exerciseDate =
    DateTime(startTime.year, startTime.month, startTime.day);

    if (exerciseDate == today) {
      return 'Today';
    } else if (exerciseDate == yesterday) {
      return 'Yesterday';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${_getDayName(exerciseDate.weekday)} ${exerciseDate.day} ${months[exerciseDate.month - 1]}';
    }
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String get formattedTime {
    final hour = startTime.hour;
    final minute = startTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'pm' : 'am';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
}