import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'practice.db');
    return await openDatabase(
      path,
      version: 5, // Increment version to ensure migration
      onCreate: (db, version) async {
        // Create exercises table
        await db.execute('''
          CREATE TABLE exercises (
            exercises_id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            type TEXT,
            difficulty TEXT,
            created_at TEXT
          )
        ''');

        // Create performances table
        await db.execute('''
          CREATE TABLE performances (
            performances_id INTEGER PRIMARY KEY AUTOINCREMENT,
            exercises_id INTEGER,
            score REAL,
            attempt_time TEXT,
            recording_path TEXT,
            FOREIGN KEY (exercises_id) REFERENCES exercises (exercises_id)
          )
        ''');

        // Create practice_sessions table with flexible level validation
        await db.execute('''
          CREATE TABLE practice_sessions (
            session_id INTEGER PRIMARY KEY AUTOINCREMENT,
            level TEXT NOT NULL,
            score INTEGER NOT NULL CHECK (score >= 0),
            total_notes INTEGER NOT NULL CHECK (total_notes > 0),
            percentage REAL NOT NULL CHECK (percentage >= 0 AND percentage <= 100),
            practice_date TEXT NOT NULL,
            practice_time TEXT NOT NULL,
            duration_seconds REAL NOT NULL CHECK (duration_seconds > 0),
            player_name TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        // Add indexes for better query performance
        await db.execute('CREATE INDEX idx_practice_sessions_level ON practice_sessions(level)');
        await db.execute('CREATE INDEX idx_practice_sessions_date ON practice_sessions(practice_date)');
        await db.execute('CREATE INDEX idx_practice_sessions_created_at ON practice_sessions(created_at)');
        await db.execute('CREATE INDEX idx_performances_exercises_id ON performances(exercises_id)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add practice_sessions table for existing databases
          await db.execute('''
            CREATE TABLE practice_sessions (
              session_id INTEGER PRIMARY KEY AUTOINCREMENT,
              level TEXT NOT NULL,
              score INTEGER NOT NULL CHECK (score >= 0),
              total_notes INTEGER NOT NULL CHECK (total_notes > 0),
              percentage REAL NOT NULL CHECK (percentage >= 0 AND percentage <= 100),
              practice_date TEXT NOT NULL,
              practice_time TEXT NOT NULL,
              duration_seconds REAL NOT NULL CHECK (duration_seconds > 0),
              created_at TEXT NOT NULL
            )
          ''');
        }
        
        if (oldVersion < 3) {
          // Add exercises and performances tables for existing databases
          await db.execute('''
            CREATE TABLE exercises (
              exercises_id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              type TEXT,
              difficulty TEXT,
              created_at TEXT
            )
          ''');
          
          await db.execute('''
            CREATE TABLE performances (
              performances_id INTEGER PRIMARY KEY AUTOINCREMENT,
              exercises_id INTEGER,
              score REAL,
              attempt_time TEXT,
              recording_path TEXT,
              FOREIGN KEY (exercises_id) REFERENCES exercises (exercises_id)
            )
          ''');
          
          // Add indexes
          await db.execute('CREATE INDEX idx_performances_exercises_id ON performances(exercises_id)');
        }
        
        if (oldVersion < 4) {
          // Add player_name column to existing practice_sessions table
          await db.execute('ALTER TABLE practice_sessions ADD COLUMN player_name TEXT');
        }
        
        if (oldVersion < 5) {
          // Ensure player_name column exists (in case previous migration failed)
          try {
            await db.execute('ALTER TABLE practice_sessions ADD COLUMN player_name TEXT');
          } catch (e) {
            // Column might already exist, which is fine
            print('Player name column might already exist: $e');
          }
        }
      },
    );
  }

  // Insert Exercise
  Future<int> insertExercise(Map<String, dynamic> exercise) async {
    final db = await database;
    return await db.insert('exercises', exercise);
  }

  // Insert Performance
  Future<int> insertPerformance(Map<String, dynamic> performance) async {
    final db = await database;
    return await db.insert('performances', performance);
  }

  // Get all performances for an exercise
  Future<List<Map<String, dynamic>>> getPerformances(int exercisesId) async {
    final db = await database;
    return await db.query(
      'performances',
      where: 'exercises_id = ?',
      whereArgs: [exercisesId],
      orderBy: 'attempt_time DESC',
    );
  }

  // Get all exercises
  Future<List<Map<String, dynamic>>> getExercises() async {
    final db = await database;
    return await db.query('exercises', orderBy: 'created_at DESC');
  }

  // Get practice sessions by level
  Future<List<Map<String, dynamic>>> getPracticeSessionsByLevel(String level) async {
    final db = await database;
    return await db.query(
      'practice_sessions',
      where: 'level = ?',
      whereArgs: [level],
      orderBy: 'created_at DESC',
    );
  }

  // Get practice statistics
  Future<Map<String, dynamic>> getPracticeStatistics() async {
    final db = await database;
    
    // Single query instead of multiple queries
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalSessions,
        AVG(percentage) as averageScore,
        MAX(percentage) as bestScore,
        SUM(duration_seconds) as totalPracticeTime
      FROM practice_sessions
    ''');
    
    final row = result.first;
    return {
      'totalSessions': row['totalSessions'] ?? 0,
      'averageScore': (row['averageScore'] as num?)?.toDouble() ?? 0.0,
      'bestScore': (row['bestScore'] as num?)?.toDouble() ?? 0.0,
      'totalPracticeTime': (row['totalPracticeTime'] as num?)?.toDouble() ?? 0.0,
    };
  }

  // Clear all practice sessions (for testing purposes)
  Future<void> clearAllPracticeSessions() async {
    final db = await database;
    await db.delete('practice_sessions');
  }

  // Get sessions by date range
  Future<List<Map<String, dynamic>>> getSessionsByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    return await db.query(
      'practice_sessions',
      where: 'practice_date BETWEEN ? AND ?',
      whereArgs: [
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}'
      ],
      orderBy: 'created_at DESC',
    );
  }

  // Get best session for each level
  Future<Map<String, Map<String, dynamic>>> getBestSessionsByLevel() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT level, MAX(percentage) as best_percentage, 
             score, total_notes, practice_date, practice_time
      FROM practice_sessions 
      GROUP BY level
    ''');
    
    Map<String, Map<String, dynamic>> bestSessions = {};
    for (var row in result) {
      bestSessions[row['level'] as String] = row;
    }
    return bestSessions;
  }

  // Get practice streak
  Future<int> getCurrentStreak() async {
    final db = await database;
    final today = DateTime.now();
    int streak = 0;
    
    for (int i = 0; i < 365; i++) {
      final checkDate = today.subtract(Duration(days: i));
      final dateStr = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
      
      final result = await db.query(
        'practice_sessions',
        where: 'practice_date = ?',
        whereArgs: [dateStr],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        streak++;
      } else {
        break;
      }
    }
    
    return streak;
  }

  // Get weekly progress
  Future<List<Map<String, dynamic>>> getWeeklyProgress() async {
    final db = await database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    
    return await db.rawQuery('''
      SELECT 
        practice_date,
        COUNT(*) as sessions_count,
        AVG(percentage) as avg_percentage,
        SUM(duration_seconds) as total_time
      FROM practice_sessions 
      WHERE practice_date >= ?
      GROUP BY practice_date
      ORDER BY practice_date DESC
    ''', ['${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}']);
  }

  // Add pagination for large datasets
  Future<List<Map<String, dynamic>>> getPracticeSessions({int limit = 50, int offset = 0}) async {
    final db = await database;
    return await db.query(
      'practice_sessions',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  // Validate data before inserting - Updated to be more flexible
  bool _validateSessionData(Map<String, dynamic> session) {
    final level = session['level'] as String?;
    final score = session['score'] as int?;
    final totalNotes = session['total_notes'] as int?;
    final percentage = session['percentage'] as double?;
    
    // More flexible level validation - allow any non-empty string
    if (level == null || level.isEmpty) return false;
    if (score == null || score < 0) return false;
    if (totalNotes == null || totalNotes <= 0) return false;
    if (percentage == null || percentage < 0 || percentage > 100) return false;
    
    return true;
  }

  // Enhanced insert method with validation
  Future<int> insertPracticeSession(Map<String, dynamic> session) async {
    if (!_validateSessionData(session)) {
      throw ArgumentError('Invalid session data');
    }
    
    final db = await database;
    return await db.insert('practice_sessions', session);
  }

  // Clean up old data (optional)
  Future<void> cleanupOldSessions({int daysToKeep = 365}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final cutoffStr = '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';
    
    await db.delete(
      'practice_sessions',
      where: 'practice_date < ?',
      whereArgs: [cutoffStr],
    );
  }

  // Get database size info
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalSessions,
        MIN(created_at) as firstSession,
        MAX(created_at) as lastSession
      FROM practice_sessions
    ''');
    
    return result.first;
  }
}