import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'controllers/exercise_controller.dart';
import 'controllers/pedometer_controller.dart';
import 'controllers/location_controller.dart';
import 'views/exercise_list_view.dart';

void main() {
  runApp(const FitnessApp());
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({Key? key}) : super(key: key);

  //component
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExerciseController()),
        ChangeNotifierProvider(create: (_) => PedometerController()),
        ChangeNotifierProvider(create: (_) => LocationController()),
      ],
      child: MaterialApp(
        title: 'Fitness Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.purple,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          fontFamily: 'SF Pro Display', // Or your preferred font
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
            bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C6FDC),
          ),
        ),
        home: const ExerciseListView(),
      ),
    );
  }
}