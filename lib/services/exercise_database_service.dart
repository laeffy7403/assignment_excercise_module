import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/exercise.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'fitness_app.db');

    return await openDatabase(
      path,
      version: 2, // FIX: bumped from 1 → 2 to trigger onUpgrade
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // FIX: Added stepGoal, distanceGoal, timeGoal columns that were missing
    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type INTEGER NOT NULL,
        startTime TEXT NOT NULL,
        durationMinutes INTEGER NOT NULL,
        distanceKm REAL,
        energyExpended INTEGER,
        steps INTEGER,
        notes TEXT,
        routePoints TEXT,
        createdAt TEXT NOT NULL,
        stepGoal INTEGER,
        distanceGoal REAL,
        timeGoal INTEGER
      )
    ''');
  }

  // FIX: Migrate existing installs that are on version 1 (missing goal columns)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE exercises ADD COLUMN stepGoal INTEGER');
      await db.execute('ALTER TABLE exercises ADD COLUMN distanceGoal REAL');
      await db.execute('ALTER TABLE exercises ADD COLUMN timeGoal INTEGER');
    }
  }

  // Create - Insert new exercise
  Future<String> insertExercise(Exercise exercise) async {
    final db = await database;
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final exerciseWithId = exercise.copyWith(id: id);

    await db.insert(
      'exercises',
      exerciseWithId.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return id;
  }

  // Read - Get all exercises
  Future<List<Exercise>> getAllExercises() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      orderBy: 'startTime DESC',
    );

    return List.generate(maps.length, (i) {
      return Exercise.fromJson(maps[i]);
    });
  }

  // Read - Get exercise by ID
  Future<Exercise?> getExerciseById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Exercise.fromJson(maps.first);
  }

  // Read - Get exercises by date range
  Future<List<Exercise>> getExercisesByDateRange(
      DateTime start,
      DateTime end,
      ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      where: 'startTime >= ? AND startTime <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'startTime DESC',
    );

    return List.generate(maps.length, (i) {
      return Exercise.fromJson(maps[i]);
    });
  }

  // Read - Get exercises by type
  Future<List<Exercise>> getExercisesByType(ExerciseType type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      where: 'type = ?',
      whereArgs: [type.index],
      orderBy: 'startTime DESC',
    );

    return List.generate(maps.length, (i) {
      return Exercise.fromJson(maps[i]);
    });
  }

  // Update - Update existing exercise
  Future<int> updateExercise(Exercise exercise) async {
    final db = await database;
    return await db.update(
      'exercises',
      exercise.toJson(),
      where: 'id = ?',
      whereArgs: [exercise.id],
    );
  }

  // Delete - Delete exercise by ID
  Future<int> deleteExercise(String id) async {
    final db = await database;
    return await db.delete(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Delete - Delete all exercises
  Future<int> deleteAllExercises() async {
    final db = await database;
    return await db.delete('exercises');
  }

  // Get total count of exercises
  Future<int> getExerciseCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM exercises');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}