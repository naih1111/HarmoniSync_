import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/music_service.dart';
import '../widgets/music_sheet.dart';
import 'converted_music_screen.dart';

class SheetConverterScreen extends StatefulWidget {
  const SheetConverterScreen({super.key});

  @override
  State<SheetConverterScreen> createState() => _SheetConverterScreenState();
}

class _SheetConverterScreenState extends State<SheetConverterScreen> with SingleTickerProviderStateMixin {
  // Converted items (persisted on device)
  final List<Map<String, String>> _convertedItems = [];
  
  // Brand colors
  static const Color _brandPrimary = Color(0xFF8B4511);
  static const Color _brandAccent = Color(0xFF424242);
  
  // Conversion settings - Choose the appropriate URL based on your setup:
  // For Android Emulator: 'http://10.0.2.2:5000'
  // For Physical Device: 'http://192.168.100.51:5000' (your computer's IP)
  // For Desktop/Web: 'http://localhost:5000'
  static const String _serverUrl = 'http://192.168.1.9:5000';
  bool _isConverting = false; // Track conversion status
  String? _conversionError; // Store any conversion errors
  
  // Holds the last picked file to display during conversion
  String? _currentConvertingName;
  
  // Temp buffer (not shown anymore)
  final Map<String, String> _conversionResults = {};

  // Loader animation
  late final AnimationController _loaderController;

  @override
  void initState() {
    super.initState();
    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadConvertedItems(); // Add this line
  }

  @override
  void dispose() {
    _loaderController.dispose();
    super.dispose();
  }

  /// Load previously converted items from SharedPreferences and scan for existing files
  Future<void> _loadConvertedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedItems = prefs.getStringList('converted_items') ?? [];
      
      // Convert saved items back to list of maps
      final List<Map<String, String>> items = [];
      for (final itemJson in savedItems) {
        final item = Map<String, String>.from(jsonDecode(itemJson));
        // Verify the file still exists
        if (await File(item['path'] ?? '').exists()) {
          items.add(item);
        }
      }
      
      // Also scan documents directory for any MusicXML files that might not be in the list
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      for (final file in files) {
        if (file is File && file.path.endsWith('.musicxml')) {
          final fileName = p.basename(file.path);
          final pdfName = fileName.replaceAll('.musicxml', '.pdf');
          
          // Check if this file is already in our list
          final exists = items.any((item) => item['name'] == pdfName);
          if (!exists) {
            items.add({'name': pdfName, 'path': file.path});
          }
        }
      }
      
      setState(() {
        _convertedItems.clear();
        _convertedItems.addAll(items);
      });
    } catch (e) {
      print('Error loading converted items: $e');
    }
  }

  /// Save converted items to SharedPreferences
  Future<void> _saveConvertedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final itemsJson = _convertedItems.map((item) => jsonEncode(item)).toList();
      await prefs.setStringList('converted_items', itemsJson);
    } catch (e) {
      print('Error saving converted items: $e');
    }
  }

  /// Load MusicXML from a file path and parse it into a Score object
  Future<Score?> _loadMusicXMLFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File does not exist: $filePath');
        return null;
      }
      
      final xmlString = await file.readAsString();
      final score = Score.fromXML(xmlString);
      return score;
    } catch (e) {
      print('Error loading MusicXML from file: $e');
      return null;
    }
  }

  /// Open and display a converted MusicXML file
  Future<void> _openMusicSheet(String filePath, String fileName) async {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConvertedMusicScreen(
            filePath: filePath,
            fileName: fileName,
          ),
        ),
      );
    }
  }

  Future<String> _saveMusicXml(String content, String pdfFileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final xmlFileName = pdfFileName.replaceAll('.pdf', '.musicxml');
    final file = File('${directory.path}/$xmlFileName');
    await file.writeAsString(content);
    return file.path;
  }

  Future<void> _pickPdfFile() async {
    try {
      // Request storage permission on Android
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+), use different permissions
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
          if (!status.isGranted) {
            // Fallback to storage permission for older Android versions
            status = await Permission.storage.status;
            if (!status.isGranted) {
              status = await Permission.storage.request();
              if (!status.isGranted) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Storage permission is required to select PDF files'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
            }
          }
        }
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false, // single file per flow
        withData: false, // Don't load file data into memory
        withReadStream: false, // Don't create read stream
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        // Validate file path
        if (file.path == null || file.path!.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid file path. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Validate file exists
        final fileObj = File(file.path!);
        if (!await fileObj.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Selected file does not exist. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Validate file size (limit to 50MB)
        final fileSize = await fileObj.length();
        const maxSize = 50 * 1024 * 1024; // 50MB
        if (fileSize > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File size too large. Please select a PDF smaller than 50MB.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Validate file extension
        if (!file.name.toLowerCase().endsWith('.pdf')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a valid PDF file.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        setState(() {
          _currentConvertingName = file.name;
          _isConverting = true;
          _conversionError = null;
        });
        
        // auto-start conversion
        await _convertPdfToMusicXml(fileObj);
      }
    } catch (e) {
      setState(() {
        _isConverting = false;
        _currentConvertingName = null;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePdf(int index) async {
    final item = _convertedItems[index];
    // Delete the actual file
    try {
      final file = File(item['path'] ?? '');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
    
    setState(() {
      _convertedItems.removeAt(index);
    });
    
    // Save the updated list
    await _saveConvertedItems();
  }

  // ==========================================================================
  // PDF TO MUSICXML CONVERSION - Connect to local Python Flask server
  // ==========================================================================
  
  /// Convert a PDF file to MusicXML using the local Flask server with Audiveris
  Future<void> _convertPdfToMusicXml(File pdfFile) async {
    try {
      setState(() {
        _isConverting = true;
        _conversionError = null;
      });

      // First, test server connection
      try {
        final healthResponse = await http.get(
          Uri.parse('$_serverUrl/health'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        
        if (healthResponse.statusCode != 200) {
          throw Exception('Server health check failed with status: ${healthResponse.statusCode}');
        }
      } catch (e) {
        setState(() {
          _conversionError = 'Cannot connect to server: $e';
          _isConverting = false;
          _currentConvertingName = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Server connection failed: $e\nPlease check if the server is running at $_serverUrl'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Proceed with conversion
      final uri = Uri.parse('$_serverUrl/convert');
      final request = http.MultipartRequest('POST', uri);
      
      // Add file with proper headers
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        pdfFile.path,
        filename: p.basename(pdfFile.path),
      ));

      // Set timeout for the request
      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          final musicXml = (result['musicxml'] as String?) ?? '';
          
          if (musicXml.isEmpty) {
            throw Exception('Server returned empty MusicXML content');
          }
          
          final savedPath = await _saveMusicXml(musicXml, p.basename(pdfFile.path));

          setState(() {
            final fileName = p.basename(pdfFile.path);
            _conversionResults[fileName] = savedPath;
            _convertedItems.insert(0, {'name': fileName, 'path': savedPath});
            _isConverting = false;
            _currentConvertingName = null;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully converted: ${p.basename(pdfFile.path)}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          setState(() {
            _conversionError = 'Failed to parse server response: $e';
            _isConverting = false;
            _currentConvertingName = null;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to parse server response: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        String errorMessage = 'Server error: ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage += ' - ${errorBody['error'] ?? response.body}';
        } catch (e) {
          errorMessage += ' - ${response.body}';
        }
        
        setState(() {
          _conversionError = errorMessage;
          _isConverting = false;
          _currentConvertingName = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Conversion failed: $errorMessage'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _conversionError = 'Connection error: $e';
        _isConverting = false;
        _currentConvertingName = null;
      });

      if (mounted) {
        String errorMsg = 'Connection failed: $e';
        if (e.toString().contains('TimeoutException')) {
          errorMsg = 'Request timed out. The server may be processing a large file.';
        } else if (e.toString().contains('SocketException')) {
          errorMsg = 'Cannot connect to server. Please check the server URL and ensure it\'s running.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    
    // Save the updated list
    await _saveConvertedItems();
  }

  /// Convert all PDF files in the list (placeholder for future multi-select)
  Future<void> _convertAllPdfs() async {
    // For this UX, we convert on pick; keep for potential batch mode
    if (_currentConvertingName != null) return;
  }

  /// Show server settings dialog
  void _showServerSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current URL: $_serverUrl'),
            const SizedBox(height: 16),
            const Text('Available URLs:'),
            const Text('• http://192.168.100.51:5000 (Physical Device)'),
            const Text('• http://10.0.2.2:5000 (Android Emulator)'),
            const Text('• http://localhost:5000 (Desktop/Web)'),
            const SizedBox(height: 16),
            const Text('Update _serverUrl in SheetConverterScreen to change it.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _testServerConnection();
            },
            child: const Text('Test Connection'),
          ),
        ],
      ),
    );
  }

  /// Test connection to the Flask server
  Future<void> _testServerConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server connection successful!\nServer URL: $_serverUrl'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server responded with status: ${response.statusCode}\nResponse: ${response.body}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      String errorMsg = 'Cannot connect to server: $e';
      if (e.toString().contains('TimeoutException')) {
        errorMsg = 'Connection timed out. Please check if the server is running at $_serverUrl';
      } else if (e.toString().contains('SocketException')) {
        errorMsg = 'Network error. Please check your connection and server URL: $_serverUrl';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B4511),
        foregroundColor: Color(0xFFF5F5DD),
        title: const Text('Sheet Converter'),
        centerTitle: true,
      ),
      floatingActionButton: _convertedItems.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isConverting ? null : _pickPdfFile,
              backgroundColor: _brandPrimary,
              foregroundColor: Color(0xFFF5F5DD),
              icon: _isConverting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFF5F5DD),
                      ),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isConverting ? 'Converting...' : 'Upload PDF'),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.9, -0.8),
            end: Alignment(1.0, 0.9),
            colors: [
              Color(0xFFFFF9C4),
              Color(0xFFFFECB3),
              Color(0xFFE3F2FD),
              Color(0xFFBBDEFB),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _convertedItems.isEmpty
                      ? Column(
                          key: const ValueKey('initial'),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                              Icons.library_music,
                              size: 120,
                              color: _brandPrimary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'PDF to MusicXML',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: _brandPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload a PDF to begin conversion',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF8B4511).withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 28),
                            ElevatedButton.icon(
                              onPressed: _isConverting ? null : _pickPdfFile,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brandPrimary,
                                foregroundColor: Color(0xFFF5F5DD),
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('results'),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                children: [
                                  Text(
                                    'Converted Files',
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: _brandPrimary),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B4511).withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text('${_convertedItems.length}', style: theme.textTheme.labelLarge),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                itemCount: _convertedItems.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: const Color(0xFF8B4511).withOpacity(0.07)),
                                itemBuilder: (context, index) {
                                  final item = _convertedItems[index];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _brandPrimary.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _brandPrimary.withOpacity(0.08)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: _brandPrimary.withOpacity(0.12),
                                          child: Icon(Icons.music_note, color: _brandPrimary),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['name'] ?? 'Unknown',
                                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item['path'] ?? '',
                                                style: theme.textTheme.bodySmall?.copyWith(color: Color(0xFF8B4511).withOpacity(0.54)),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.open_in_new),
                                              color: _brandAccent,
                                              tooltip: 'Open',
                                              onPressed: () => _openMusicSheet(item['path'] ?? '', item['name'] ?? ''),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.ios_share),
                                              color: _brandAccent,
                                              tooltip: 'Share',
                                              onPressed: () {
                                                // share hook
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline),
                                              color: Colors.red,
                                              tooltip: 'Delete',
                                              onPressed: () => _removePdf(index),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                ),
              ],
            ),
          ),
              ),
            ),
            if (_isConverting) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: const Color(0xFF8B4511).withOpacity(0.25),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Color(0xFFF5F5DD),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF8B4511).withOpacity(0.15),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated equalizer bars
                      SizedBox(
                        width: 96,
                        height: 48,
                        child: AnimatedBuilder(
                          animation: _loaderController,
                          builder: (context, _) {
                            // 5 bars with phase offsets
                            final phases = [0.0, 0.15, 0.3, 0.45, 0.6];
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(phases.length, (i) {
                                final t = (_loaderController.value + phases[i]) % 1.0;
                                // Smooth wave (0.4..1.0)
                                final h = 12 + 36 * (0.5 + 0.5 * math.sin(2 * 3.1415926 * t));
                                return Container(
                                  width: 10,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: _brandAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Subtle progress line
                      SizedBox(
                        width: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            backgroundColor: Color(0xFF8B4511).withOpacity(0.07),
                            color: _brandAccent,
                            minHeight: 4,
                            value: (_loaderController.value * 0.6) + 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Converting',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (_currentConvertingName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _currentConvertingName!,
                          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF8B4511).withOpacity(0.54)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
