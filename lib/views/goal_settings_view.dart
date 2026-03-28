import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoalSettingsView extends StatefulWidget {
  const GoalSettingsView({Key? key}) : super(key: key);

  @override
  State<GoalSettingsView> createState() => _GoalSettingsViewState();
}

class _GoalSettingsViewState extends State<GoalSettingsView> {
  int _stepGoal = 10000;
  double _distanceGoal = 5.0;
  int _calorieGoal = 500;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _stepGoal = prefs.getInt('step_goal') ?? 10000;
      _distanceGoal = prefs.getDouble('distance_goal') ?? 5.0;
      _calorieGoal = prefs.getInt('calorie_goal') ?? 500;
      _isLoading = false;
    });
  }

  Future<void> _saveGoals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('step_goal', _stepGoal);
    await prefs.setDouble('distance_goal', _distanceGoal);
    await prefs.setInt('calorie_goal', _calorieGoal);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goals saved!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Goals',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saveGoals,
            child: const Text(
              'Save',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C6FDC), Color(0xFF9D8FE8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.flag,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Daily Goals',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your targets and track your progress',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Step Goal
          _buildGoalCard(
            icon: Icons.directions_walk,
            iconColor: const Color(0xFF4CAF50),
            title: 'Daily Steps',
            subtitle: 'Number of steps per day',
            value: _stepGoal.toDouble(),
            unit: 'steps',
            minValue: 100, // set back to 1000 default
            maxValue: 50000,
            divisions: 49,
            onChanged: (value) {
              setState(() {
                _stepGoal = value.round();
              });
            },
          ),
          const SizedBox(height: 20),

          // Distance Goal
          _buildGoalCard(
            icon: Icons.straighten,
            iconColor: const Color(0xFF2196F3),
            title: 'Daily Distance',
            subtitle: 'Distance to cover per day',
            value: _distanceGoal.toDouble(),
            unit: 'km',
            minValue: 1.0,
            maxValue: 20.0,
            divisions: 38,
            onChanged: (value) {
              setState(() {
                _distanceGoal = (value * 2).round() / 2; // Round to 0.5
              });
            },
          ),
          const SizedBox(height: 20),

          // Calorie Goal
          _buildGoalCard(
            icon: Icons.local_fire_department,
            iconColor: const Color(0xFFFF9800),
            title: 'Daily Calories',
            subtitle: 'Calories to burn per day',
            value: _calorieGoal.toDouble(),
            unit: 'cal',
            minValue: 100,
            maxValue: 2000,
            divisions: 38,
            onChanged: (value) {
              setState(() {
                _calorieGoal = (value / 50).round() * 50; // Round to nearest 50
              });
            },
          ),
          const SizedBox(height: 32),

          // Quick Presets
          const Text(
            'Quick Presets',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPresetButton(
                'Beginner',
                '5K steps',
                    () {
                  setState(() {
                    _stepGoal = 5000;
                    _distanceGoal = 3.0;
                    _calorieGoal = 250;
                  });
                },
              ),
              const SizedBox(width: 12),
              _buildPresetButton(
                'Intermediate',
                '10K steps',
                    () {
                  setState(() {
                    _stepGoal = 10000;
                    _distanceGoal = 5.0;
                    _calorieGoal = 500;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildPresetButton(
                'Advanced',
                '15K steps',
                    () {
                  setState(() {
                    _stepGoal = 15000;
                    _distanceGoal = 10.0;
                    _calorieGoal = 750;
                  });
                },
              ),
              const SizedBox(width: 12),
              _buildPresetButton(
                'Athlete',
                '20K steps',
                    () {
                  setState(() {
                    _stepGoal = 20000;
                    _distanceGoal = 15.0;
                    _calorieGoal = 1000;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required double value,
    required String unit,
    required double minValue,
    required double maxValue,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(1)} $unit',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7C6FDC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: iconColor,
              inactiveTrackColor: iconColor.withOpacity(0.2),
              thumbColor: iconColor,
              overlayColor: iconColor.withOpacity(0.2),
              trackHeight: 6,
            ),
            child: Slider(
              value: value,
              min: minValue,
              max: maxValue,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String title, String subtitle, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7C6FDC)),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C6FDC),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Static method to get current step goal
  static Future<int> getStepGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('step_goal') ?? 10000;
  }

  static Future<double> getDistanceGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('distance_goal') ?? 5.0;
  }

  static Future<int> getCalorieGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('calorie_goal') ?? 500;
  }
}