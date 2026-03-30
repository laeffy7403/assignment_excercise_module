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
      version: 3, // bumped from 2 → 3 to add isAutoDetected column
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
        timeGoal INTEGER,
        isAutoDetected INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE exercises ADD COLUMN stepGoal INTEGER');
      await db.execute('ALTER TABLE exercises ADD COLUMN distanceGoal REAL');
      await db.execute('ALTER TABLE exercises ADD COLUMN timeGoal INTEGER');
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE exercises ADD COLUMN isAutoDetected INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

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

  Future<int> updateExercise(Exercise exercise) async {
    final db = await database;
    return await db.update(
      'exercises',
      exercise.toJson(),
      where: 'id = ?',
      whereArgs: [exercise.id],
    );
  }

  Future<int> deleteExercise(String id) async {
    final db = await database;
    return await db.delete(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllExercises() async {
    final db = await database;
    return await db.delete('exercises');
  }

  Future<int> getExerciseCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM exercises');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}