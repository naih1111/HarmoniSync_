import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'dart:math' as math;

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _practiceSessions = [];
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgressData();
  }

  Future<void> _loadProgressData() async {
    try {
      setState(() => _isLoading = true);
      
      print('Loading progress data...');
      final sessions = await _dbHelper.getPracticeSessions();
      print('Found ${sessions.length} practice sessions');
      
      final stats = await _dbHelper.getPracticeStatistics();
      print('Statistics: $stats');
      
      setState(() {
        _practiceSessions = sessions;
        _statistics = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading progress data: $e');
    }
  }

  Future<void> _addSampleData() async {
    try {
      print('Adding sample data...');
      final now = DateTime.now();
      
      // Add some sample practice sessions for testing
      final sampleSessions = [
        {
          'level': '1',
          'score': 8,
          'total_notes': 10,
          'percentage': 80.0,
          'practice_date': '${now.year}-${(now.month - 2).toString().padLeft(2, '0')}-${(now.day - 5).toString().padLeft(2, '0')}',
          'practice_time': '14:30',
          'duration_seconds': 45.2,
          'created_at': now.subtract(const Duration(days: 60)).toIso8601String(),
        },
        {
          'level': '1',
          'score': 9,
          'total_notes': 10,
          'percentage': 90.0,
          'practice_date': '${now.year}-${(now.month - 1).toString().padLeft(2, '0')}-${(now.day - 3).toString().padLeft(2, '0')}',
          'practice_time': '16:15',
          'duration_seconds': 38.7,
          'created_at': now.subtract(const Duration(days: 30)).toIso8601String(),
        },
        {
          'level': '2',
          'score': 7,
          'total_notes': 12,
          'percentage': 58.3,
          'practice_date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day - 7).toString().padLeft(2, '0')}',
          'practice_time': '10:45',
          'duration_seconds': 67.3,
          'created_at': now.subtract(const Duration(days: 7)).toIso8601String(),
        },
        {
          'level': '2',
          'score': 10,
          'total_notes': 12,
          'percentage': 83.3,
          'practice_date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day - 2).toString().padLeft(2, '0')}',
          'practice_time': '19:20',
          'duration_seconds': 52.1,
          'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        },
        {
          'level': '3',
          'score': 5,
          'total_notes': 15,
          'percentage': 33.3,
          'practice_date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day - 1).toString().padLeft(2, '0')}',
          'practice_time': '21:10',
          'duration_seconds': 89.5,
          'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        },
      ];

      for (final session in sampleSessions) {
        print('Inserting session: $session');
        final id = await _dbHelper.insertPracticeSession(session);
        print('Inserted with ID: $id');
      }

      // Reload the data to show the new sessions
      await _loadProgressData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sample data added! You can now see your progress.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding sample data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllData() async {
    try {
      // Clear all practice sessions
      await _dbHelper.clearAllPracticeSessions();
      
      // Reload the data
      await _loadProgressData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data cleared!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testDatabase() async {
    try {
      print('Testing database connection...');
      
      // Test database connection
      final db = await _dbHelper.database;
      print('Database connected successfully');
      
      // Test table creation
      final tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
      print('Available tables: ${tables.map((t) => t['name']).toList()}');
      
      // Test inserting a simple record
      final testSession = {
        'level': 'TEST',
        'score': 1,
        'total_notes': 1,
        'percentage': 100.0,
        'practice_date': '2024-01-01',
        'practice_time': '00:00',
        'duration_seconds': 1.0,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      print('Inserting test session...');
      final id = await _dbHelper.insertPracticeSession(testSession);
      print('Test session inserted with ID: $id');
      
      // Test reading it back
      final sessions = await _dbHelper.getPracticeSessions();
      print('Found ${sessions.length} sessions after test insert');
      
      // Clean up test data
      await _dbHelper.clearAllPracticeSessions();
      print('Test data cleaned up');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database test completed! Check console for details.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Database test failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B4511),
        foregroundColor: Color(0xFFF5F5DD),
        title: const Text('Progress Tracker'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F4E1),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadProgressData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatisticsCards(),
                      const SizedBox(height: 24),
                      _buildLevelProgress(),
                      const SizedBox(height: 24),
                      _buildPracticeHistory(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        _buildStatCard(
          'Total Sessions',
          '${_statistics['totalSessions'] ?? 0}',
          Icons.play_circle_filled,
          Colors.blue,
        ),
        _buildStatCard(
          'Best Score',
          '${_statistics['bestScore']?.toStringAsFixed(1) ?? '0'}%',
          Icons.star,
          Colors.amber,
        ),
        _buildStatCard(
          'Average Score',
          '${_statistics['averageScore']?.toStringAsFixed(1) ?? '0'}%',
          Icons.trending_up,
          Colors.green,
        ),
        _buildStatCard(
          'Total Time',
          _formatDuration(_statistics['totalPracticeTime'] ?? 0),
          Icons.timer,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF5F5DD),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B4511).withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
              child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B4511).withOpacity(0.87),
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildLevelProgress() {
    final levelStats = <String, Map<String, dynamic>>{};
    
    // Group sessions by level
    for (final session in _practiceSessions) {
      final level = session['level'] as String;
      if (!levelStats.containsKey(level)) {
        levelStats[level] = {
          'totalSessions': 0,
          'bestScore': 0.0,
          'averageScore': 0.0,
          'totalTime': 0.0,
        };
      }
      
      levelStats[level]!['totalSessions'] = levelStats[level]!['totalSessions'] + 1;
      levelStats[level]!['bestScore'] = math.max(levelStats[level]!['bestScore'] as double, session['percentage'] as double);
      levelStats[level]!['totalTime'] = levelStats[level]!['totalTime'] + (session['duration_seconds'] as double);
    }
    
    // Calculate averages
    for (final level in levelStats.keys) {
      final sessions = _practiceSessions.where((s) => s['level'] == level).toList();
      final totalScore = sessions.fold<double>(0.0, (sum, s) => sum + (s['percentage'] as double));
      levelStats[level]!['averageScore'] = totalScore / sessions.length;
    }

    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF5F5DD),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B4511).withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Text(
                'Level Progress',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...levelStats.entries.map((entry) {
            final level = entry.key;
            final stats = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Level $level',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${stats['totalSessions']} sessions',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (stats['averageScore'] / 100).clamp(0.0, 1.0),
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getScoreColor(stats['averageScore']),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${stats['averageScore'].toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _getScoreColor(stats['averageScore']),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Best: ${stats['bestScore'].toStringAsFixed(1)}% | Time: ${_formatDuration(stats['totalTime'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPracticeHistory() {
    if (_practiceSessions.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Color(0xFFF5F5DD),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B4511).withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Practice Sessions Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete your first exercise to see your progress here!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFF5F5DD),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Text(
                'Recent Practice Sessions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _practiceSessions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final session = _practiceSessions[index];
              return _buildSessionTile(session);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> session) {
    final level = session['level'] as String;
    final score = session['score'] as int;
    final totalNotes = session['total_notes'] as int;
    final percentage = session['percentage'] as double;
    final date = session['practice_date'] as String;
    final time = session['practice_time'] as String;
    final duration = session['duration_seconds'] as double;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _getScoreColor(percentage).withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            'L$level',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _getScoreColor(percentage),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Level $level Exercise',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: _getScoreColor(percentage),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            'Score: $score / $totalNotes | Duration: ${_formatDuration(duration)}',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'Date: $date at $time',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 90) return Colors.green;
    if (percentage >= 70) return Colors.orange;
    if (percentage >= 50) return Colors.yellow[700]!;
    return Colors.red;
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(0)}s';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = (seconds % 60).round();
      return '${minutes}m ${remainingSeconds}s';
    } else {
      final hours = (seconds / 3600).floor();
      final remainingMinutes = ((seconds % 3600) / 60).round();
      return '${hours}h ${remainingMinutes}m';
    }
  }
}
