import '../models/exercise.dart';

class CalorieCalculator {
  // MET (Metabolic Equivalent of Task) values for different exercises
  // These are approximate values based on moderate intensity
  static const Map<ExerciseType, double> _metValues = {
    ExerciseType.walking: 3.5,   // Moderate pace (3-4 mph)
    ExerciseType.jogging: 7.0,   // Moderate pace (5-6 mph)
    ExerciseType.running: 9.8,   // Fast pace (7+ mph)
  };

  // Average weight in kg for calculation (can be customized per user)
  static const double _defaultWeightKg = 70.0;

  /// Estimate calories burned based on exercise type, duration, and distance
  /// Formula: Calories = MET × weight(kg) × time(hours)
  int estimateCalories({
    required ExerciseType type,
    required int durationMinutes,
    required double distanceKm,
    double? weightKg,
  }) {
    final weight = weightKg ?? _defaultWeightKg;
    final met = _metValues[type] ?? 5.0;
    final hours = durationMinutes / 60.0;

    // Basic MET calculation
    double calories = met * weight * hours;

    // Adjust based on pace (distance/time) if available
    if (distanceKm > 0) {
      final paceKmPerHour = distanceKm / hours;
      calories = _adjustForPace(calories, type, paceKmPerHour);
    }

    return calories.round();
  }

  /// Estimate calories from steps
  /// Approximate: 0.04-0.05 calories per step for average person
  int estimateCaloriesFromSteps(int steps, {double? weightKg}) {
    final weight = weightKg ?? _defaultWeightKg;
    // Calories per step varies with weight
    final caloriesPerStep = 0.04 * (weight / 70.0); // Normalized to 70kg
    return (steps * caloriesPerStep).round();
  }

  /// Adjust calories based on pace/intensity
  double _adjustForPace(
      double baseCalories,
      ExerciseType type,
      double paceKmPerHour,
      ) {
    double multiplier = 1.0;

    switch (type) {
      case ExerciseType.walking:
      // Walking pace adjustment
        if (paceKmPerHour < 4.0) {
          multiplier = 0.85; // Slow walk
        } else if (paceKmPerHour > 6.0) {
          multiplier = 1.2; // Brisk walk
        }
        break;

      case ExerciseType.jogging:
      // Jogging pace adjustment
        if (paceKmPerHour < 7.0) {
          multiplier = 0.9; // Light jog
        } else if (paceKmPerHour > 10.0) {
          multiplier = 1.15; // Fast jog
        }
        break;

      case ExerciseType.running:
      // Running pace adjustment
        if (paceKmPerHour < 9.0) {
          multiplier = 0.85; // Moderate run
        } else if (paceKmPerHour > 12.0) {
          multiplier = 1.25; // Fast run
        }
        break;
    }

    return baseCalories * multiplier;
  }

  /// Get estimated pace in km/h
  double calculatePace(double distanceKm, int durationMinutes) {
    if (durationMinutes == 0) return 0.0;
    final hours = durationMinutes / 60.0;
    return distanceKm / hours;
  }

  /// Get pace description
  String getPaceDescription(ExerciseType type, double paceKmPerHour) {
    switch (type) {
      case ExerciseType.walking:
        if (paceKmPerHour < 4.0) return 'Leisurely';
        if (paceKmPerHour < 5.5) return 'Moderate';
        if (paceKmPerHour < 6.5) return 'Brisk';
        return 'Very brisk';

      case ExerciseType.jogging:
        if (paceKmPerHour < 7.0) return 'Light';
        if (paceKmPerHour < 9.0) return 'Moderate';
        if (paceKmPerHour < 11.0) return 'Fast';
        return 'Very fast';

      case ExerciseType.running:
        if (paceKmPerHour < 9.0) return 'Moderate';
        if (paceKmPerHour < 11.0) return 'Fast';
        if (paceKmPerHour < 13.0) return 'Very fast';
        return 'Sprint';
    }
  }

  /// Estimate distance from steps
  /// Average step length: ~0.7-0.8 meters
  double estimateDistanceFromSteps(int steps, {double stepLengthMeters = 0.75}) {
    return (steps * stepLengthMeters) / 1000.0; // Convert to km
  }

  /// Estimate steps from distance
  int estimateStepsFromDistance(double distanceKm, {double stepLengthMeters = 0.75}) {
    return ((distanceKm * 1000.0) / stepLengthMeters).round();
  }
}