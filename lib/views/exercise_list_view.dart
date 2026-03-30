import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../controllers/exercise_controller.dart';
import '../controllers/pedometer_controller.dart';
import '../models/exercise.dart';
import 'exercise_add_view.dart';
import 'exercise_detail_view.dart';
import 'exercise_live_view.dart';
import 'exercise_goal_settings_view.dart';

class ExerciseListView extends StatefulWidget {
  const ExerciseListView({Key? key}) : super(key: key);

  @override
  State<ExerciseListView> createState() => _ExerciseListViewState();
}

class _ExerciseListViewState extends State<ExerciseListView> {
  // FIX (banner freeze): tick every 30 s so the displayed duration stays fresh.
  Timer? _bannerRefreshTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pedometer =
      Provider.of<PedometerController>(context, listen: false);
      pedometer.startAutoDetect();
    });

    // Redraw every 30 seconds so "X min" in the banner stays current
    _bannerRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _bannerRefreshTimer?.cancel();
    super.dispose();
  }

  // ── Save the auto-detected walk ─────────────────────────────────────────────
  Future<void> _saveAutoDetectedWalk(BuildContext context) async {
    final pedometer =
    Provider.of<PedometerController>(context, listen: false);
    final exerciseController =
    Provider.of<ExerciseController>(context, listen: false);

    final startTime = pedometer.autoDetectStartTime ?? DateTime.now();
    final durationMinutes =
    DateTime.now().difference(startTime).inMinutes.clamp(1, 9999);
    final steps = pedometer.autoDetectedSteps;

    String title = '';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final titleController = TextEditingController(
          text: 'Walk ${TimeOfDay.fromDateTime(startTime).format(context)}',
        );
        return AlertDialog(
          title: const Text('Save detected walk'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'e.g. Afternoon Walk',
              border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                pedometer.dismissAutoDetect();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C6FDC),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                title = titleController.text.trim();
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (title.isEmpty) return; // user cancelled

    final exercise = Exercise(
      title: title,
      type: ExerciseType.walking,
      startTime: startTime,
      durationMinutes: durationMinutes,
      steps: steps > 0 ? steps : null,
    );

    final success = await exerciseController.createExercise(exercise);
    pedometer.resetAutoDetect();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Walk saved!' : 'Failed to save walk'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: const Text(
                'exercise',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87),
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Consumer2<ExerciseController, PedometerController>(
                  builder: (context, controller, pedometer, child) {
                    if (controller.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // ── Auto-walk banner ───────────────────────────────
                        if (pedometer.isAutoWalkDetected)
                          _buildAutoWalkBanner(context, pedometer),

                        // Start Workout Card
                        _buildStartWorkoutCard(context),
                        const SizedBox(height: 24),

                        // Today's Log
                        if (controller.todayExercises.isNotEmpty) ...[
                          _buildSectionHeader("Today's Log"),
                          const SizedBox(height: 16),
                          ...controller.todayExercises
                              .map((e) => _buildExerciseCard(context, e)),
                          const SizedBox(height: 24),
                        ],

                        // Past Log
                        if (controller.pastExercises.isNotEmpty) ...[
                          _buildSectionHeader('Past exercise Log'),
                          const SizedBox(height: 16),
                          ...controller.pastExercises
                              .map((e) => _buildExerciseCard(context, e)),
                        ],

                        if (controller.exercises.isEmpty)
                          _buildEmptyState(context),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const AddExerciseView()),
            );
          },
          backgroundColor: const Color(0xFFD1D1D1),
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  // ── Auto-walk banner ────────────────────────────────────────────────────────
  Widget _buildAutoWalkBanner(
      BuildContext context, PedometerController pedometer) {
    final startTime = pedometer.autoDetectStartTime;

    // FIX (banner freeze): compute elapsed fresh every build; _bannerRefreshTimer
    // calls setState every 30 s so this value actually updates.
    final elapsed = startTime != null
        ? DateTime.now().difference(startTime)
        : Duration.zero;
    final minutes = elapsed.inMinutes;
    final steps = pedometer.autoDetectedSteps;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF43A047).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_walk,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Walk detected!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    Provider.of<PedometerController>(context, listen: false)
                        .dismissAutoDetect(),
                child:
                const Icon(Icons.close, color: Colors.white70, size: 20),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _buildBannerStat(
                  Icons.access_time, '$minutes min', 'Duration'),
              const SizedBox(width: 12),
              if (steps > 0)
                _buildBannerStat(Icons.directions_walk, '$steps', 'Steps'),
            ],
          ),

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _saveAutoDetectedWalk(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'Save Walk',
                        style: TextStyle(
                          color: Color(0xFF43A047),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Provider.of<PedometerController>(context, listen: false)
                        .resetAutoDetect();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveExerciseView(
                          exerciseType: ExerciseType.walking,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white60),
                    ),
                    child: const Center(
                      child: Text(
                        'Track Live',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBannerStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style:
                const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  // ── Existing widgets ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
          fontSize: 16,
          color: Colors.grey[600],
          fontWeight: FontWeight.w400),
    );
  }

  Widget _buildStartWorkoutCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6FDC), Color(0xFF9D8FE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C6FDC).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_circle_filled,
                  color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Start a Workout',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const GoalSettingsView()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Track your activity in real-time with GPS and step counting',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildQuickStartButton(context, ExerciseType.walking, 'Walking',
                  Icons.directions_walk),
              const SizedBox(width: 12),
              _buildQuickStartButton(context, ExerciseType.jogging, 'Jogging',
                  Icons.run_circle),
              const SizedBox(width: 12),
              _buildQuickStartButton(context, ExerciseType.running, 'Running',
                  Icons.directions_run),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartButton(
      BuildContext context, ExerciseType type, String label, IconData icon) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Provider.of<PedometerController>(context, listen: false)
              .resetAutoDetect();
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => LiveExerciseView(exerciseType: type)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border:
            Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(BuildContext context, Exercise exercise) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ExerciseDetailView(exercise: exercise)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'exercise created at ${exercise.formattedTime}',
                    style:
                    TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exercise.title.isNotEmpty
                        ? exercise.title
                        : exercise.type.displayName,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${exercise.formattedDistance} in ${exercise.formattedDuration}',
                    style:
                    TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(exercise.formattedDate,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                      const Spacer(),
                      if (exercise.steps != null)
                        Text(exercise.formattedSteps,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: exercise.type.color.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                exercise.type.icon,
                color: exercise.type.color.withOpacity(0.9),
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No exercises yet',
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Tap the + button to add your first exercise',
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.person_outline, 'Profile', false),
              _buildNavItem(Icons.fitness_center, 'Workout', false),
              _buildNavItem(Icons.access_time, 'Activity', true),
              _buildNavItem(Icons.favorite_border, 'Health', false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFE8E3FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon,
              color:
              isActive ? const Color(0xFF7C6FDC) : Colors.grey[600],
              size: 26),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? const Color(0xFF7C6FDC)
                    : Colors.grey[600],
                fontWeight:
                isActive ? FontWeight.w500 : FontWeight.w400)),
      ],
    );
  }
}