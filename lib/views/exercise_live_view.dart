import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';

import '../controllers/exercise_controller.dart';
import '../controllers/pedometer_controller.dart';
import '../controllers/location_controller.dart';
import '../models/exercise.dart';
import '../services/exercise_notification_service.dart';

class LiveExerciseView extends StatefulWidget {
  final ExerciseType exerciseType;
  final int? stepGoal;

  const LiveExerciseView({
    Key? key,
    required this.exerciseType,
    this.stepGoal,
  }) : super(key: key);

  @override
  State<LiveExerciseView> createState() => _LiveExerciseViewState();
}

class _LiveExerciseViewState extends State<LiveExerciseView>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final NotificationService _notificationService = NotificationService();
  Timer? _timer;

  // Workout state
  bool _isTracking = false;

  // Wall-clock based timing (fixes timer freeze when phone locked)
  DateTime? _startTime;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pausedAt;
  int _elapsedSeconds = 0;

  // Initial step count
  int _initialSteps = 0;

  // Goals from settings
  int? _loadedStepGoal;
  double? _loadedDistanceGoal;
  int? _loadedTimeGoal;

  // Goal achievement tracking
  bool _stepGoalNotified = false;
  bool _distanceGoalNotified = false;
  bool _timeGoalNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGoals();
    _initializeTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isTracking) {
      _syncElapsedFromWallClock();
    }
  }

  void _syncElapsedFromWallClock() {
    if (_startTime == null) return;
    final wallElapsed =
        DateTime.now().difference(_startTime!) - _pausedDuration;
    if (mounted) {
      setState(() {
        _elapsedSeconds = wallElapsed.inSeconds.clamp(0, 999999);
      });
    }
  }

  Future<void> _loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _loadedStepGoal = widget.stepGoal ?? prefs.getInt('step_goal') ?? 5000;
      _loadedDistanceGoal = prefs.getDouble('distance_goal') ?? 5.0;
      _loadedTimeGoal = prefs.getInt('time_goal') ?? 30;
    });
  }

  Future<void> _initializeTracking() async {
    final pedometerController =
    Provider.of<PedometerController>(context, listen: false);
    final locationController =
    Provider.of<LocationController>(context, listen: false);

    await _notificationService.initialize();

    final pedometerInit = await pedometerController.initialize();
    final locationInit = await locationController.initialize();

    if (!pedometerInit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedometer not available. Steps won\'t be tracked.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    if (!locationInit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available. GPS tracking disabled.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    await locationController.getCurrentLocation();
  }

  void _startWorkout() async {
    final pedometerController =
    Provider.of<PedometerController>(context, listen: false);
    final locationController =
    Provider.of<LocationController>(context, listen: false);

    final now = DateTime.now();
    setState(() {
      _isTracking = true;
      _startTime = now;
      _elapsedSeconds = 0;
      _pausedDuration = Duration.zero;
      _pausedAt = null;
      _stepGoalNotified = false;
      _distanceGoalNotified = false;
      _timeGoalNotified = false;
    });

    await WakelockPlus.enable();

    // Reset BEFORE startTracking so initial GPS point is preserved
    pedometerController.resetSession();
    locationController.resetRoute();

    await pedometerController.startTracking();
    await locationController.startTracking();

    _initialSteps = pedometerController.totalSteps;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.exerciseType.displayName} started!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _syncElapsedFromWallClock();
      _checkGoals();
    });
  }

  void _checkGoals() {
    final pedometerController =
    Provider.of<PedometerController>(context, listen: false);
    final locationController =
    Provider.of<LocationController>(context, listen: false);

    if (_loadedStepGoal != null && !_stepGoalNotified) {
      if (pedometerController.sessionSteps >= _loadedStepGoal!) {
        _notificationService.notifyStepGoalReached(
          pedometerController.sessionSteps,
          _loadedStepGoal!,
        );
        _stepGoalNotified = true;
      }
    }

    if (_loadedDistanceGoal != null && !_distanceGoalNotified) {
      if (locationController.totalDistance >= _loadedDistanceGoal!) {
        _notificationService.notifyDistanceGoalReached(
          locationController.totalDistance,
          _loadedDistanceGoal!,
        );
        _distanceGoalNotified = true;
      }
    }

    if (_loadedTimeGoal != null && !_timeGoalNotified) {
      final minutesElapsed = _elapsedSeconds ~/ 60;
      if (minutesElapsed >= _loadedTimeGoal!) {
        _notificationService.notifyTimeGoalReached(_loadedTimeGoal!);
        _timeGoalNotified = true;
      }
    }
  }

  void _pauseWorkout() {
    setState(() {
      _isTracking = false;
      _pausedAt = DateTime.now();
    });
    _timer?.cancel();
  }

  void _resumeWorkout() {
    if (_pausedAt != null) {
      _pausedDuration += DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
    }
    setState(() {
      _isTracking = true;
    });
    _startTimer();
  }

  // Step 1: confirm they want to stop
  void _showStopConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Workout?'),
        content: Text(
          'Duration: ${_formatDuration(_elapsedSeconds)}\n'
              'This will save your workout to the exercise log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showTitleDialog(); // Step 2: let them name it
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }

  // Step 2: let user name the workout before saving
  void _showTitleDialog() {
    final autoTitle =
        '${widget.exerciseType.displayName} ${_formatDuration(_elapsedSeconds)}';
    final titleController = TextEditingController(text: autoTitle);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your workout'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g. Morning Walk',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _stopWorkout(titleController.text.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopWorkout(''); // empty → auto-generate in Exercise model
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopWorkout(titleController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C6FDC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _stopWorkout(String title) async {
    _timer?.cancel();
    await WakelockPlus.disable();
    await _notificationService.cancelProgressNotification();

    final pedometerController =
    Provider.of<PedometerController>(context, listen: false);
    final locationController =
    Provider.of<LocationController>(context, listen: false);
    final exerciseController =
    Provider.of<ExerciseController>(context, listen: false);

    pedometerController.stopTracking();
    locationController.stopTracking();

    final exercise = Exercise(
      title: title, // '' triggers auto-generate inside Exercise model
      type: widget.exerciseType,
      startTime: _startTime!,
      durationMinutes: (_elapsedSeconds / 60).round().clamp(1, 9999),
      distanceKm: locationController.totalDistance,
      steps: pedometerController.sessionSteps,
      routePoints: locationController.routePoints.toList(),
      stepGoal: _loadedStepGoal,
      distanceGoal: _loadedDistanceGoal,
      timeGoal: _loadedTimeGoal,
    );

    final success = await exerciseController.createExercise(exercise);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Workout saved!'
              : 'Failed to save: ${exerciseController.error ?? "unknown error"}'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Workout?'),
        content: const Text(
            'Your workout is still in progress. Exit without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pedometerController =
              Provider.of<PedometerController>(context, listen: false);
              final locationController =
              Provider.of<LocationController>(context, listen: false);

              _timer?.cancel();
              WakelockPlus.disable();
              pedometerController.stopTracking();
              locationController.stopTracking();

              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // White background removes the black gap between map and stats panel
      backgroundColor: Colors.white,
      body: Consumer3<PedometerController, LocationController,
          ExerciseController>(
        builder: (context, pedometerController, locationController,
            exerciseController, child) {
          final currentSteps = pedometerController.sessionSteps;
          final currentDistance = locationController.totalDistance;
          final currentSpeed = locationController.currentSpeed ?? 0.0;
          final stepGoalProgress = _loadedStepGoal != null
              ? (currentSteps / _loadedStepGoal!).clamp(0.0, 1.0)
              : 0.0;

          // Move map to follow user on every location update
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isTracking && locationController.currentLatLng != null) {
              try {
                _mapController.move(
                    locationController.currentLatLng!, 17.0);
              } catch (_) {}
            }
          });

          return SafeArea(
            child: Column(
              children: [
                // ── Map View ───────────────────────────────────────────
                // ClipRRect clips the map to have rounded bottom corners,
                // eliminating the black gap against the white stats panel.
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    child: Stack(
                      children: [
                        locationController.currentLatLng != null
                            ? FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter:
                            locationController.currentLatLng!,
                            initialZoom: 17.0,
                            minZoom: 3.0,
                            maxZoom: 19.0,
                            keepAlive: true,
                            interactionOptions: InteractionOptions(
                              flags: InteractiveFlag.all &
                              ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                              'com.example.assignment_excercise_module',
                              maxZoom: 19,
                            ),

                            // Route polyline
                            if (locationController
                                .routeLatLngs.length >=
                                2)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: locationController
                                        .routeLatLngs,
                                    color: const Color(0xFF2196F3),
                                    strokeWidth: 5.0,
                                    borderColor: Colors.white,
                                    borderStrokeWidth: 2.0,
                                  ),
                                ],
                              ),

                            // Markers
                            MarkerLayer(
                              markers: [
                                if (locationController
                                    .routeLatLngs.isNotEmpty)
                                  Marker(
                                    point: locationController
                                        .routeLatLngs.first,
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white,
                                            width: 3),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withOpacity(0.3),
                                            blurRadius: 6,
                                            offset:
                                            const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(Icons.flag,
                                          color: Colors.white,
                                          size: 20),
                                    ),
                                  ),
                                if (_isTracking &&
                                    locationController
                                        .currentLatLng !=
                                        null)
                                  Marker(
                                    point: locationController
                                        .currentLatLng!,
                                    width: 50,
                                    height: 50,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                        const Color(0xFF2196F3),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white,
                                            width: 4),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue
                                                .withOpacity(0.5),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                          Icons.navigation,
                                          color: Colors.white,
                                          size: 24),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        )
                            : const Center(
                          child: Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                  color: Colors.blue),
                              SizedBox(height: 16),
                              Text('Getting your location...',
                                  style: TextStyle(
                                      color: Colors.white70)),
                            ],
                          ),
                        ),

                        // Back button
                        Positioned(
                          top: 16,
                          left: 16,
                          child: GestureDetector(
                            onTap: () {
                              if (_isTracking) {
                                _showExitConfirmation();
                              } else {
                                Navigator.pop(context);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.arrow_back,
                                  color: Colors.black87),
                            ),
                          ),
                        ),

                        // Exercise type badge
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: widget.exerciseType.color
                                  .withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.exerciseType.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        // "Runs in background" badge
                        if (_isTracking)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_clock,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Runs in background',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                          ),

                        // OSM attribution
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('© OpenStreetMap',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54)),
                          ),
                        ),
                      ],
                    ), // Stack
                  ),   // ClipRRect
                ),

                // ── Stats Panel ─────────────────────────────────────────
                // OVERFLOW FIX: removed Spacer() — it was pushing content
                // outside the flex:2 budget. Use MainAxisAlignment
                // .spaceBetween on the Column instead, and shrink padding
                // + font sizes slightly so everything fits comfortably.
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Timer + subtitle
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatDuration(_elapsedSeconds),
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _startTime != null
                                  ? 'Started at ${TimeOfDay.fromDateTime(_startTime!).format(context)}'
                                  : 'Ready to start',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600]),
                            ),
                          ],
                        ),

                        // Stats Grid
                        Row(
                          children: [
                            _buildStatCard(
                              icon: Icons.directions_walk,
                              label: 'Steps',
                              value: currentSteps.toString(),
                              goal: _loadedStepGoal != null
                                  ? '/$_loadedStepGoal'
                                  : null,
                              progress: stepGoalProgress,
                            ),
                            const SizedBox(width: 10),
                            _buildStatCard(
                              icon: Icons.straighten,
                              label: 'Distance',
                              value: currentDistance.toStringAsFixed(2),
                              unit: 'km',
                            ),
                            const SizedBox(width: 10),
                            _buildStatCard(
                              icon: Icons.speed,
                              label: 'Speed',
                              value: currentSpeed.toStringAsFixed(1),
                              unit: 'km/h',
                            ),
                          ],
                        ),

                        // Control buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_startTime != null) ...[
                              _buildControlButton(
                                icon: Icons.stop,
                                color: Colors.red,
                                onPressed: _showStopConfirmation,
                              ),
                              const SizedBox(width: 20),
                            ],
                            _buildControlButton(
                              icon: _startTime == null
                                  ? Icons.play_arrow
                                  : _isTracking
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: const Color(0xFF4CAF50),
                              size: 62,
                              iconSize: 32,
                              onPressed: () {
                                if (_startTime == null) {
                                  _startWorkout();
                                } else if (_isTracking) {
                                  _pauseWorkout();
                                } else {
                                  _resumeWorkout();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    String? unit,
    String? goal,
    double? progress,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold),
              maxLines: 1,
            ),
            if (goal != null || unit != null)
              Text(
                '${goal ?? ''}${unit ?? ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            if (progress != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress >= 1.0
                        ? Colors.green
                        : const Color(0xFF4CAF50),
                  ),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 60,
    double iconSize = 30,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}