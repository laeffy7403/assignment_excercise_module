import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// ── Auto-Walk Detection + Auto-Save ───────────────────────────────────────────
//
// BEHAVIOUR
//   • Cadence is sampled every 10 s (same as before).
//   • After CONFIRM_WINDOWS consecutive active windows → walk detected.
//   • After IDLE_RESET_WINDOWS of no steps  → walk stopped.
//     At that point the walk is AUTO-SAVED via the [onAutoSave] callback
//     instead of just resetting silently.
//   • Hard cap: if a walk exceeds MAX_AUTO_DETECT_MINUTES without stopping,
//     it is force-saved to avoid recording huge sessions / draining battery.
//   • The saved Exercise will have isAutoDetected = true, so the detail view
//     can lock the numeric fields.
//
// CHANGES vs previous version
//   • Added [onAutoSave] callback — set from ExerciseListView.
//   • Added _autoSaveTimer for the MAX_AUTO_DETECT_MINUTES cap.
//   • _triggerAutoSave() builds the Exercise and fires the callback.
//   • resetAutoDetect() cancels the save timer too.

typedef AutoSaveCallback = void Function({
required DateTime startTime,
required int steps,
required int durationMinutes,
});

class PedometerController extends ChangeNotifier {
  // ── Step counting ───────────────────────────────────────────────────────────
  int _totalSteps = 0;
  int _sessionSteps = 0;
  int _sessionStartSteps = 0;

  // ── Pedometer streams ───────────────────────────────────────────────────────
  StreamSubscription<StepCount>? _manualStepSubscription;
  StreamSubscription<StepCount>? _autoDetectStepSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;

  // ── Status ──────────────────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _isWalking = false;
  String? _error;

  // ── Auto-walk detection state ───────────────────────────────────────────────
  static const int _walkCadenceThreshold = 40; // steps/min minimum
  static const int _confirmWindows = 3;         // consecutive windows to confirm
  static const int _idleResetWindows = 6;       // idle windows → auto-save + reset

  /// Hard cap: auto-save the walk after this many minutes even if still active.
  /// Prevents runaway sessions and reduces battery impact.
  static const int maxAutoDetectMinutes = 90;

  Timer? _cadenceTimer;
  Timer? _autoSaveTimer; // fires after maxAutoDetectMinutes
  int _lastCadenceStepCount = 0;
  int _confirmCount = 0;
  int _idleCount = 0;

  bool _isAutoWalkDetected = false;
  bool _autoDetectDismissed = false;
  DateTime? _autoDetectStartTime;
  int _autoDetectBaseSteps = 0;

  /// Called when the controller decides the walk is over (idle timeout or
  /// max-duration cap). The listener (ExerciseListView) creates the Exercise.
  AutoSaveCallback? onAutoSave;

  // ── Getters ─────────────────────────────────────────────────────────────────
  int get totalSteps => _totalSteps;
  int get sessionSteps => _sessionSteps;
  bool get isTracking => _isTracking;
  bool get isWalking => _isWalking;
  String? get error => _error;

  bool get isAutoWalkDetected => _isAutoWalkDetected && !_autoDetectDismissed;

  int get autoDetectedSteps =>
      _isAutoWalkDetected
          ? (_totalSteps - _autoDetectBaseSteps).clamp(0, 999999)
          : 0;

  DateTime? get autoDetectStartTime => _autoDetectStartTime;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

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

  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
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

  void stopTracking() {
    _manualStepSubscription?.cancel();
    _manualStepSubscription = null;
    _pedestrianStatusSubscription?.cancel();
    _pedestrianStatusSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  void resetSession() {
    _sessionStartSteps = _totalSteps;
    _sessionSteps = 0;
    notifyListeners();
  }

  // ── Auto-walk detection public API ──────────────────────────────────────────

  Future<void> startAutoDetect() async {
    if (_cadenceTimer != null) return;

    final ok = await initialize();
    if (!ok) return;

    _autoDetectStepSubscription ??= Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
    );

    _lastCadenceStepCount = _totalSteps;

    _cadenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _evaluateCadence();
    });
  }

  void stopAutoDetect() {
    _cadenceTimer?.cancel();
    _cadenceTimer = null;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    _autoDetectStepSubscription?.cancel();
    _autoDetectStepSubscription = null;

    _resetInternalState();
    notifyListeners();
  }

  void dismissAutoDetect() {
    _autoDetectDismissed = true;
    notifyListeners();
  }

  /// Full reset — called after the user manually starts a live workout,
  /// or after an auto-save has been processed by the listener.
  void resetAutoDetect() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

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
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
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

    final cadencePerMin = stepsDelta * 6; // 10-s window → steps/min

    if (cadencePerMin >= _walkCadenceThreshold) {
      _idleCount = 0;
      _confirmCount++;

      if (!_isAutoWalkDetected && _confirmCount >= _confirmWindows) {
        // ── Walk confirmed ─────────────────────────────────────────────
        _isAutoWalkDetected = true;
        _autoDetectDismissed = false;

        _autoDetectStartTime = DateTime.now().subtract(
          Duration(seconds: _confirmWindows * 10),
        );
        _autoDetectBaseSteps = _totalSteps;

        // Start the hard-cap timer
        _autoSaveTimer?.cancel();
        _autoSaveTimer = Timer(
          Duration(minutes: maxAutoDetectMinutes),
              () => _triggerAutoSave(reason: 'max_duration'),
        );

        notifyListeners();
      }
    } else {
      if (_isAutoWalkDetected) {
        _idleCount++;
        if (_idleCount >= _idleResetWindows) {
          // Stopped walking → auto-save then reset
          _triggerAutoSave(reason: 'idle');
        }
      } else {
        // Decay confirm count when not yet confirmed
        _confirmCount = (_confirmCount - 1).clamp(0, _confirmWindows);
      }
    }
  }

  /// Fires [onAutoSave] then resets state so the next walk can be detected.
  void _triggerAutoSave({required String reason}) {
    if (!_isAutoWalkDetected) return;

    final startTime = _autoDetectStartTime ?? DateTime.now();
    final durationMinutes =
    DateTime.now().difference(startTime).inMinutes.clamp(1, 9999);
    final steps = autoDetectedSteps;

    // Fire the callback BEFORE resetting so the listener captures correct data
    onAutoSave?.call(
      startTime: startTime,
      steps: steps,
      durationMinutes: durationMinutes,
    );

    // Reset so the next walk starts fresh
    resetAutoDetect();
  }

  // ── Pedometer callbacks ─────────────────────────────────────────────────────

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