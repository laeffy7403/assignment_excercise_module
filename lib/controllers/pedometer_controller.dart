import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// ── Auto-Walk Detection ────────────────────────────────────────────────────────
// How it works:
//   • Monitors the pedometer's raw step count every 10 seconds via a periodic timer.
//   • Computes a rolling cadence (steps/min) per window.
//   • If cadence ≥ WALK_CADENCE_THRESHOLD for CONFIRM_WINDOWS consecutive
//     windows → sets `isAutoWalkDetected = true`.
//   • Stops detecting after IDLE_RESET_WINDOWS of no steps.
//   • Dismiss / Save Walk resets state so the next walk can be detected.
//
// FIX SUMMARY (5 bugs fixed):
//   1. Step baseline was device cumulative total — now records a snapshot
//      (_autoDetectBaseSteps) at the moment detection fires, not estimated back.
//   2. _autoDetectStartSteps wrong arithmetic — removed, replaced with snapshot.
//   3. Separate stream subscription for autoDetect prevents collision with
//      manual session subscription (stopTracking no longer kills autoDetect).
//   4. stopAutoDetect properly cancels its own subscription.
//   5. _confirmCount was never reset on idle when not yet detected — caused
//      false triggers after prolonged low-cadence movement.

class PedometerController extends ChangeNotifier {
  // ── Step counting ───────────────────────────────────────────────────────────
  int _totalSteps = 0;
  int _sessionSteps = 0;
  int _sessionStartSteps = 0;

  // ── Pedometer streams ───────────────────────────────────────────────────────
  // FIX 3: two separate subscriptions — one for manual session, one for
  // background auto-detect.  stopTracking() only cancels the manual one.
  StreamSubscription<StepCount>? _manualStepSubscription;
  StreamSubscription<StepCount>? _autoDetectStepSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;

  // ── Status ──────────────────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _isWalking = false;
  String? _error;

  // ── Auto-walk detection state ───────────────────────────────────────────────
  static const int _walkCadenceThreshold = 40; // steps/min minimum
  static const int _confirmWindows = 3;         // consecutive windows needed
  static const int _idleResetWindows = 6;       // idle windows before reset

  Timer? _cadenceTimer;
  int _lastCadenceStepCount = 0;
  int _confirmCount = 0;
  int _idleCount = 0;

  bool _isAutoWalkDetected = false;
  bool _autoDetectDismissed = false;
  DateTime? _autoDetectStartTime;

  // FIX 1 & 2: snapshot of _totalSteps at the moment detection fires.
  // autoDetectedSteps = _totalSteps - _autoDetectBaseSteps (always >= 0).
  int _autoDetectBaseSteps = 0;

  // ── Getters ─────────────────────────────────────────────────────────────────
  int get totalSteps => _totalSteps;
  int get sessionSteps => _sessionSteps;
  bool get isTracking => _isTracking;
  bool get isWalking => _isWalking;
  String? get error => _error;

  /// True when a walk is auto-detected and the banner has not been dismissed.
  bool get isAutoWalkDetected => _isAutoWalkDetected && !_autoDetectDismissed;

  /// Steps counted since auto-detect fired (always ≥ 0).
  int get autoDetectedSteps =>
      _isAutoWalkDetected
          ? (_totalSteps - _autoDetectBaseSteps).clamp(0, 999999)
          : 0;

  /// When auto-detection began (for the banner's duration display).
  DateTime? get autoDetectStartTime => _autoDetectStartTime;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Request the activity-recognition permission.
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

  // ── Manual session tracking ─────────────────────────────────────────────────

  /// Start a manual workout session.
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      // FIX 3: use the dedicated manual subscription
      _manualStepSubscription = Pedometer.stepCountStream.listen(
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

  /// Stop the manual workout session only — does NOT affect auto-detect.
  void stopTracking() {
    // FIX 3: cancel only the manual subscription
    _manualStepSubscription?.cancel();
    _manualStepSubscription = null;
    _pedestrianStatusSubscription?.cancel();
    _pedestrianStatusSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Reset session step counter (call before starting a new exercise).
  void resetSession() {
    _sessionStartSteps = _totalSteps;
    _sessionSteps = 0;
    notifyListeners();
  }

  // ── Auto-walk detection public API ──────────────────────────────────────────

  /// Call from ExerciseListView.initState() to run the background monitor.
  Future<void> startAutoDetect() async {
    if (_cadenceTimer != null) return; // already running

    final ok = await initialize();
    if (!ok) return;

    // FIX 3: dedicated subscription — independent of manual session
    _autoDetectStepSubscription ??= Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
    );

    _lastCadenceStepCount = _totalSteps;

    // Sample every 10 seconds
    _cadenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _evaluateCadence();
    });
  }

  /// Stop the background cadence monitor and clean up.
  void stopAutoDetect() {
    _cadenceTimer?.cancel();
    _cadenceTimer = null;

    // FIX 4: cancel the auto-detect subscription too
    _autoDetectStepSubscription?.cancel();
    _autoDetectStepSubscription = null;

    _resetInternalState();
    notifyListeners();
  }

  /// User tapped "Dismiss" — hide the banner but keep detecting.
  void dismissAutoDetect() {
    _autoDetectDismissed = true;
    notifyListeners();
  }

  /// User saved or started a manual workout — full reset so next walk can fire.
  void resetAutoDetect() {
    _isAutoWalkDetected = false;
    _autoDetectDismissed = false;
    _autoDetectStartTime = null;
    _autoDetectBaseSteps = 0;
    _confirmCount = 0;
    _idleCount = 0;
    _lastCadenceStepCount = _totalSteps;
    notifyListeners();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _resetInternalState() {
    _isAutoWalkDetected = false;
    _autoDetectDismissed = false;
    _autoDetectStartTime = null;
    _autoDetectBaseSteps = 0;
    _confirmCount = 0;
    _idleCount = 0;
  }

  void _evaluateCadence() {
    final stepsDelta = _totalSteps - _lastCadenceStepCount;
    _lastCadenceStepCount = _totalSteps;

    // 10-second window → steps/min
    final cadencePerMin = stepsDelta * 6;

    if (cadencePerMin >= _walkCadenceThreshold) {
      _idleCount = 0;
      _confirmCount++;

      if (!_isAutoWalkDetected && _confirmCount >= _confirmWindows) {
        // ── Walking confirmed ──────────────────────────────────────────────
        _isAutoWalkDetected = true;
        _autoDetectDismissed = false;

        // Backdate start time to cover the full confirmation window
        _autoDetectStartTime = DateTime.now().subtract(
          Duration(seconds: _confirmWindows * 10),
        );

        // FIX 1 & 2: record a clean step snapshot RIGHT NOW.
        // Steps gained during the look-back are small and acceptable to ignore
        // rather than risk negative/huge numbers from bad arithmetic.
        _autoDetectBaseSteps = _totalSteps;

        notifyListeners();
      }
    } else {
      // No meaningful steps this window
      if (_isAutoWalkDetected) {
        _idleCount++;
        if (_idleCount >= _idleResetWindows) {
          // Stopped walking — reset so next walk can be detected
          resetAutoDetect();
        }
      } else {
        // FIX 5: decay confirm count when not yet detected, don't just clamp
        _confirmCount = (_confirmCount - 1).clamp(0, _confirmWindows);
      }
    }
  }

  // ── Pedometer callbacks (shared by both subscriptions) ─────────────────────

  void _onStepCount(StepCount event) {
    _totalSteps = event.steps;
    if (_isTracking) {
      if (_sessionStartSteps == 0) _sessionStartSteps = _totalSteps;
      _sessionSteps = _totalSteps - _sessionStartSteps;
    }
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