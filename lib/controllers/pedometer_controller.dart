import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class PedometerController extends ChangeNotifier {
  // Step counting
  int _totalSteps = 0;
  int _sessionSteps = 0;
  int _sessionStartSteps = 0;

  // Pedometer streams
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;

  // Status
  bool _isTracking = false;
  bool _isWalking = false;
  String? _error;

  // Getters
  int get totalSteps => _totalSteps;
  int get sessionSteps => _sessionSteps;
  bool get isTracking => _isTracking;
  bool get isWalking => _isWalking;
  String? get error => _error;

  /// Initialize pedometer and request permissions
  Future<bool> initialize() async {
    try {
      // Request activity recognition permission (Android)
      final status = await Permission.activityRecognition.request();

      if (status.isDenied || status.isPermanentlyDenied) {
        _error = 'Activity recognition permission denied';
        notifyListeners();
        return false;
      }

      return true;
    } catch (e) {
      _error = 'Failed to initialize pedometer: $e';
      notifyListeners();
      return false;
    }
  }

  /// Start tracking steps
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      // Start step count stream
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );

      // Start pedestrian status stream
      _pedestrianStatusSubscription = Pedometer.pedestrianStatusStream.listen(
        _onPedestrianStatus,
        onError: _onPedestrianStatusError,
      );

      _isTracking = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start tracking: $e';
      _isTracking = false;
      notifyListeners();
    }
  }

  /// Stop tracking steps
  void stopTracking() {
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();

    _stepCountSubscription = null;
    _pedestrianStatusSubscription = null;

    _isTracking = false;
    notifyListeners();
  }

  /// Reset session steps (for starting a new exercise)
  void resetSession() {
    _sessionStartSteps = _totalSteps;
    _sessionSteps = 0;
    notifyListeners();
  }

  /// Handle step count updates
  void _onStepCount(StepCount event) {
    _totalSteps = event.steps;

    // Calculate session steps
    if (_sessionStartSteps == 0) {
      _sessionStartSteps = _totalSteps;
    }
    _sessionSteps = _totalSteps - _sessionStartSteps;

    notifyListeners();
  }

  /// Handle step count errors
  void _onStepCountError(error) {
    _error = 'Step count error: $error';
    notifyListeners();
  }

  /// Handle pedestrian status updates
  void _onPedestrianStatus(PedestrianStatus event) {
    _isWalking = event.status == 'walking';
    notifyListeners();
  }

  /// Handle pedestrian status errors
  void _onPedestrianStatusError(error) {
    // Pedestrian status errors are less critical
    debugPrint('Pedestrian status error: $error');
  }

  /// Get current step count (useful for one-time checks)
  Future<int?> getCurrentStepCount() async {
    try {
      final stepCount = await Pedometer.stepCountStream.first;
      return stepCount.steps;
    } catch (e) {
      _error = 'Failed to get step count: $e';
      notifyListeners();
      return null;
    }
  }

  /// Cleanup
  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}