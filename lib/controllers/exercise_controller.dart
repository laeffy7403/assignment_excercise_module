import 'package:flutter/material.dart';
import '../models/exercise.dart';
import '../services/exercise_database_service.dart';
import '../services/exercise_calorie_calculator.dart';

class ExerciseController extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final CalorieCalculator _calorieCalculator = CalorieCalculator();

  List<Exercise> _exercises = [];
  bool _isLoading = false;
  String? _error;

  List<Exercise> get exercises => _exercises;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get today's exercises
  List<Exercise> get todayExercises {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _exercises.where((exercise) {
      final exerciseDate = DateTime(
        exercise.startTime.year,
        exercise.startTime.month,
        exercise.startTime.day,
      );
      return exerciseDate == today;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // Get past exercises (not today)
  List<Exercise> get pastExercises {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _exercises.where((exercise) {
      final exerciseDate = DateTime(
        exercise.startTime.year,
        exercise.startTime.month,
        exercise.startTime.day,
      );
      return exerciseDate.isBefore(today);
    }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  ExerciseController() {
    loadExercises();
  }

  // Load all exercises from database
  Future<void> loadExercises() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _exercises = await _databaseService.getAllExercises();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load exercises: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new exercise
  Future<bool> createExercise(Exercise exercise) async {
    try {
      // Auto-calculate calories if not provided
      if (exercise.energyExpended == null && exercise.distanceKm != null) {
        exercise = exercise.copyWith(
          energyExpended: _calorieCalculator.estimateCalories(
            type: exercise.type,
            durationMinutes: exercise.durationMinutes,
            distanceKm: exercise.distanceKm!,
          ),
        );
      }

      final id = await _databaseService.insertExercise(exercise);
      exercise = exercise.copyWith(id: id);

      _exercises.add(exercise);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to create exercise: $e';
      notifyListeners();
      return false;
    }
  }

  // Read/Get a specific exercise
  Exercise? getExercise(String id) {
    try {
      return _exercises.firstWhere((exercise) => exercise.id == id);
    } catch (e) {
      return null;
    }
  }

  // Update an existing exercise
  Future<bool> updateExercise(Exercise exercise) async {
    try {
      await _databaseService.updateExercise(exercise);

      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index != -1) {
        _exercises[index] = exercise;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Failed to update exercise: $e';
      notifyListeners();
      return false;
    }
  }

  // Delete an exercise
  Future<bool> deleteExercise(String id) async {
    try {
      await _databaseService.deleteExercise(id);

      _exercises.removeWhere((exercise) => exercise.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete exercise: $e';
      notifyListeners();
      return false;
    }
  }

  // Get exercises by date range
  List<Exercise> getExercisesByDateRange(DateTime start, DateTime end) {
    return _exercises.where((exercise) {
      return exercise.startTime.isAfter(start) &&
          exercise.startTime.isBefore(end);
    }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  // Get total statistics
  Map<String, dynamic> getTotalStats() {
    int totalSteps = 0;
    double totalDistance = 0;
    int totalCalories = 0;
    int totalDuration = 0;

    for (var exercise in _exercises) {
      totalSteps += exercise.steps ?? 0;
      totalDistance += exercise.distanceKm ?? 0;
      totalCalories += exercise.energyExpended ?? 0;
      totalDuration += exercise.durationMinutes;
    }

    return {
      'totalSteps': totalSteps,
      'totalDistance': totalDistance,
      'totalCalories': totalCalories,
      'totalDuration': totalDuration,
      'totalExercises': _exercises.length,
    };
  }

  // Get statistics for a specific exercise type
  Map<String, dynamic> getStatsByType(ExerciseType type) {
    final filteredExercises = _exercises.where((e) => e.type == type).toList();

    int totalSteps = 0;
    double totalDistance = 0;
    int totalCalories = 0;
    int totalDuration = 0;

    for (var exercise in filteredExercises) {
      totalSteps += exercise.steps ?? 0;
      totalDistance += exercise.distanceKm ?? 0;
      totalCalories += exercise.energyExpended ?? 0;
      totalDuration += exercise.durationMinutes;
    }

    return {
      'totalSteps': totalSteps,
      'totalDistance': totalDistance,
      'totalCalories': totalCalories,
      'totalDuration': totalDuration,
      'totalExercises': filteredExercises.length,
    };
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}