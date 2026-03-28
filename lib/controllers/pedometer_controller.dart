import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// ── NEW FEATURE: Auto-Walk Detection ──────────────────────────────────────────
// How it works:
//   • Monitors the pedometer's raw step count every second via a periodic timer.
//   • Computes a 10-second rolling cadence (steps/min).
//   • If cadence ≥ WALK_CADENCE_THRESHOLD for CONFIRM_WINDOWS consecutive
//     windows it sets `isAutoWalkDetected = true`.
//   • Once the user dismisses the banner, or starts a manual workout, the
//     detector resets via resetAutoDetect().
//
// Thresholds (tunable):
//   WALK_CADENCE_THRESHOLD = 40 steps/min  → slow shuffle qualifies
//   CONFIRM_WINDOWS        = 3             → must stay walking for ~30 s
//   IDLE_RESET_WINDOWS     = 6             → reset after ~60 s of no steps

class PedometerController extends ChangeNotifier {
  // ── Step counting ───────────────────────────────────────────────────────────
  int _totalSteps = 0;
  int _sessionSteps = 0;
  int _sessionStartSteps = 0;

  // ── Pedometer streams ───────────────────────────────────────────────────────
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;

  // ── Status ──────────────────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _isWalking = false;
  String? _error;

  // ── Auto-walk detection state ───────────────────────────────────────────────
  static const int _walkCadenceThreshold = 40;  // steps/min minimum
  static const int _confirmWindows = 3;          // consecutive windows needed
  static const int _idleResetWindows = 6;        // idle windows before reset

  Timer? _cadenceTimer;
  int _lastCadenceStepCount = 0;
  final List<int> _cadenceWindow = [];           // steps per 10-s window
  int _confirmCount = 0;
  int _idleCount = 0;

  bool _isAutoWalkDetected = false;
  bool _autoDetectDismissed = false;
  DateTime? _autoDetectStartTime;
  int _autoDetectStartSteps = 0;

  // ── Getters ─────────────────────────────────────────────────────────────────
  int get totalSteps => _totalSteps;
  int get sessionSteps => _sessionSteps;
  bool get isTracking => _isTracking;
  bool get isWalking => _isWalking;
  String? get error => _error;

  /// True when a walk is auto-detected and the banner should show.
  bool get isAutoWalkDetected => _isAutoWalkDetected && !_autoDetectDismissed;

  /// Steps counted since auto-detect started (for the banner card).
  int get autoDetectedSteps =>
      _isAutoWalkDetected ? (_totalSteps - _autoDetectStartSteps).clamp(0, 999999) : 0;

  /// When auto-detection began (for the banner card's duration display).
  DateTime? get autoDetectStartTime => _autoDetectStartTime;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Initialize pedometer and request permissions.
  Future<bool> initialize() async {
    try {
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

  /// Start tracking steps (manual workout session).
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );
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

  /// Stop tracking steps.
  void stopTracking() {
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    _stepCountSubscription = null;
    _pedestrianStatusSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Reset session steps (for starting a new exercise).
  void resetSession() {
    _sessionStartSteps = _totalSteps;
    _sessionSteps = 0;
    notifyListeners();
  }

  // ── NEW FEATURE: Auto-walk detection public API ─────────────────────────────

  /// Call this from main.dart or ExerciseListView.initState() so the background
  /// cadence monitor runs even when no manual workout is active.
  Future<void> startAutoDetect() async {
    if (_cadenceTimer != null) return; // already running
    final ok = await initialize();
    if (!ok) return;

    // Subscribe to raw steps (background, separate from session tracking)
    _stepCountSubscription ??= Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
    );

    _lastCadenceStepCount = _totalSteps;

    // Sample every 10 seconds
    _cadenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _evaluateCadence();
    });
  }

  /// Stop the background cadence monitor.
  void stopAutoDetect() {
    _cadenceTimer?.cancel();
    _cadenceTimer = null;
    resetAutoDetect();
  }

  /// Call when the user taps "Dismiss" on the walk banner.
  void dismissAutoDetect() {
    _autoDetectDismissed = true;
    notifyListeners();
  }

  /// Call when the user taps "Save Walk" or starts a manual workout, so the
  /// banner resets and can appear again for the next detected walk.
  void resetAutoDetect() {
    _isAutoWalkDetected = false;
    _autoDetectDismissed = false;
    _autoDetectStartTime = null;
    _autoDetectStartSteps = 0;
    _confirmCount = 0;
    _idleCount = 0;
    _cadenceWindow.clear();
    _lastCadenceStepCount = _totalSteps;
    notifyListeners();
  }

  // ── Private cadence evaluation ──────────────────────────────────────────────

  void _evaluateCadence() {
    final stepsDelta = _totalSteps - _lastCadenceStepCount;
    _lastCadenceStepCount = _totalSteps;

    // Convert 10-second window → steps/min
    final cadencePerMin = stepsDelta * 6;

    if (cadencePerMin >= _walkCadenceThreshold) {
      _idleCount = 0;
      _confirmCount++;
      if (!_isAutoWalkDetected && _confirmCount >= _confirmWindows) {
        // Walking confirmed — fire detection
        _isAutoWalkDetected = true;
        _autoDetectDismissed = false;
        _autoDetectStartTime = DateTime.now().subtract(
          Duration(seconds: _confirmWindows * 10),
        );
        _autoDetectStartSteps = (_totalSteps - stepsDelta * _confirmWindows)
            .clamp(0, _totalSteps);
        notifyListeners();
      }
    } else {
      // No meaningful steps in this window
      if (_isAutoWalkDetected) {
        _idleCount++;
        if (_idleCount >= _idleResetWindows) {
          // Stopped walking — reset so a new walk can be detected
          resetAutoDetect();
        }
      } else {
        _confirmCount = (_confirmCount - 1).clamp(0, _confirmWindows);
      }
    }
  }

  // ── Pedometer stream callbacks ──────────────────────────────────────────────

  void _onStepCount(StepCount event) {
    _totalSteps = event.steps;
    if (_sessionStartSteps == 0) _sessionStartSteps = _totalSteps;
    _sessionSteps = _totalSteps - _sessionStartSteps;
    notifyListeners();
  }

  void _onStepCountError(error) {
    _error = 'Step count error: $error';
    notifyListeners();
  }

  void _onPedestrianStatus(PedestrianStatus event) {
    _isWalking = event.status == 'walking';
    notifyListeners();
  }

  void _onPedestrianStatusError(error) {
    debugPrint('Pedestrian status error: $error');
  }

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

  @override
  void dispose() {
    stopTracking();
    stopAutoDetect();
    super.dispose();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}