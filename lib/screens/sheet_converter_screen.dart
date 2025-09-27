import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:ui';
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
  // For Online Service: 'https://pdf-to-musicxml-converter.onrender.com'
  
  // Available server options:
   static const String _localServerUrl = 'http://192.168.1.8:5000'; // Keep offline option
  static const String _onlineServerUrl = 'https://pdf-to-musicxml-converter.onrender.com';
  
  // Current active server URL - switch between _localServerUrl and _onlineServerUrl
  static const String _serverUrl = _onlineServerUrl;
  bool _isConverting = false; // Track conversion status
  bool _isPickingFile = false; // Track file picking status
  bool _isOpeningFile = false; // Track file opening status
  String? _conversionError; // Store any conversion errors
  
  // Holds the last picked file to display during conversion
  String? _currentConvertingName;
  
  // Temp buffer (not shown anymore)
  final Map<String, String> _conversionResults = {};

  // Server status
  bool _serverOnline = false;
  String? _serverStatusMessage;
  Timer? _serverStatusTimer;

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
    // Initial server status check and periodic updates
    _checkServerStatus();
    _serverStatusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkServerStatus();
    });
  }

  @override
  void dispose() {
    _loaderController.dispose();
    _serverStatusTimer?.cancel();
    super.dispose();
  }

  /// Check if the device is running Android 11 (API 30) or higher
  Future<bool> _isAndroid11OrHigher() async {
    if (!Platform.isAndroid) return false;
    
    try {
      // Use a simple approach - try to check if MANAGE_EXTERNAL_STORAGE permission exists
      // This permission was introduced in Android 11 (API 30)
      final status = await Permission.manageExternalStorage.status;
      return true; // If we can check the status, the permission exists (Android 11+)
    } catch (e) {
      return false; // If there's an error, likely Android 10 or below
    }
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
    setState(() {
      _isOpeningFile = true;
    });
    
    try {
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConvertedMusicScreen(
              filePath: filePath,
              fileName: fileName,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningFile = false;
        });
      }
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
    setState(() {
      _isPickingFile = true;
    });
    
    try {
      // Request storage permission on Android
      if (Platform.isAndroid) {
        PermissionStatus status;
        
        // Check Android API level and request appropriate permissions
        if (await _isAndroid11OrHigher()) {
          // Android 11+ (API 30+) - Use MANAGE_EXTERNAL_STORAGE for full access
          status = await Permission.manageExternalStorage.status;
          if (!status.isGranted) {
            status = await Permission.manageExternalStorage.request();
            
            // If MANAGE_EXTERNAL_STORAGE is denied, try READ_EXTERNAL_STORAGE as fallback
            if (!status.isGranted) {
              status = await Permission.storage.status;
              if (!status.isGranted) {
                status = await Permission.storage.request();
              }
            }
          }
        } else {
          // Android 10 and below - Use READ_EXTERNAL_STORAGE
          status = await Permission.storage.status;
          if (!status.isGranted) {
            status = await Permission.storage.request();
          }
        }
        
        // Check final permission status
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Storage permission is required to select PDF files'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() {
            _isPickingFile = false;
          });
          return;
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
          setState(() {
            _isPickingFile = false;
          });
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
          setState(() {
            _isPickingFile = false;
          });
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
          setState(() {
            _isPickingFile = false;
          });
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
          setState(() {
            _isPickingFile = false;
          });
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

        // Validate if PDF contains music content
        setState(() {
          _isConverting = true; // Show loading indicator during validation
        });
        
        final containsMusic = await _validateMusicContent(fileObj);
        
        setState(() {
          _isConverting = false; // Hide loading indicator
        });
        
        if (!containsMusic) {
          setState(() {
            _isPickingFile = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This PDF does not appear to contain sheet music. Please select a music score PDF.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 6),
              ),
            );
          }
          return;
        }
        // Removed the success message - let the conversion result speak for itself

        setState(() {
          _currentConvertingName = file.name;
          _isConverting = true;
          _isPickingFile = false;
          _conversionError = null;
        });
        
        // auto-start conversion
        await _convertPdfToMusicXml(fileObj);
      } else {
        // No file selected, reset picking state
        setState(() {
          _isPickingFile = false;
        });
      }
    } catch (e) {
      setState(() {
        _isConverting = false;
        _isPickingFile = false;
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
    final fileName = item['name'] ?? 'Unknown file';
    
    // Show confirmation dialog
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _brandPrimary.withOpacity(0.2), width: 1),
          ),
          title: Text(
            'Delete File',
            style: TextStyle(
              color: _brandPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$fileName"?\n\nThis action cannot be undone.',
            style: TextStyle(
              color: _brandAccent,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: _brandAccent,
                backgroundColor: Colors.grey[50],
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _brandPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    
    // Only proceed if user confirmed
    if (shouldDelete == true) {
      // Delete the actual file
      try {
        final file = File(item['path'] ?? '');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      setState(() {
        _convertedItems.removeAt(index);
      });
      
      // Save the updated list
      await _saveConvertedItems();
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully deleted "$fileName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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
      bool ok = await _ensureServerAvailableWithRetry();
      if (!ok) {
        setState(() {
          _isConverting = false;
          _currentConvertingName = null;
        });
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

      print('DEBUG: Sending request to: $uri');
      print('DEBUG: File size: ${await pdfFile.length()} bytes');
      print('DEBUG: File name: ${p.basename(pdfFile.path)}');

      // Set timeout for the request
      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);

      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          final musicXml = (result['musicxml'] as String?) ?? '';
          
          if (musicXml.isEmpty) {
            throw Exception('The PDF was processed but no music notation was found. Please ensure the PDF contains clear sheet music.');
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
        String userFriendlyMessage = '';
        
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          final serverError = errorBody['error'] ?? response.body;
          errorMessage += ' - $serverError';
          
          // Provide user-friendly messages for common errors
          if (serverError.toString().toLowerCase().contains('no music') || 
              serverError.toString().toLowerCase().contains('not a music score') ||
              serverError.toString().toLowerCase().contains('no staff') ||
              serverError.toString().toLowerCase().contains('no notation')) {
            userFriendlyMessage = 'This PDF does not contain recognizable sheet music. Please ensure you\'re uploading a music score with clear notation.';
          } else if (serverError.toString().toLowerCase().contains('processing failed') ||
                     serverError.toString().toLowerCase().contains('conversion failed')) {
            userFriendlyMessage = 'Failed to process the music score. The PDF may be corrupted, have poor image quality, or contain complex notation that cannot be recognized.';
          } else if (serverError.toString().toLowerCase().contains('timeout')) {
            userFriendlyMessage = 'The conversion is taking too long. Please try with a smaller or simpler music score.';
          } else {
            userFriendlyMessage = 'Conversion failed: $serverError';
          }
        } catch (e) {
          errorMessage += ' - ${response.body}';
          userFriendlyMessage = 'Server error occurred during conversion. Please try again or check if the PDF contains valid sheet music.';
        }
        
        setState(() {
          _conversionError = errorMessage;
          _isConverting = false;
          _currentConvertingName = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userFriendlyMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
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

  /// Ensure server is available with a longer timeout and one retry (helps with cold starts)
  Future<bool> _ensureServerAvailableWithRetry() async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final resp = await http
            .get(
              Uri.parse('$_serverUrl/health'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) {
          if (!_serverOnline) {
            setState(() {
              _serverOnline = true;
              _serverStatusMessage = 'Online';
            });
          }
          return true;
        }
        // Non-200 response
        throw Exception('Server health check failed: ${resp.statusCode}');
      } catch (e) {
        if (attempt == 2) {
          setState(() {
            _serverOnline = false;
            _serverStatusMessage = 'Offline';
            _conversionError = 'Cannot connect to server: $e';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Server connection failed: $e\nPlease check if the server is running at $_serverUrl'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return false;
        }
        // Small delay before retry
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return false;
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

  /// Validate if PDF contains music-related content
  Future<bool> _validateMusicContent(File pdfFile) async {
    try {
      // Check file size first - if too large, skip detailed analysis
      final fileSize = await pdfFile.length();
      print('PDF file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // For very large files (>15MB), use quick validation only
      if (fileSize > 15 * 1024 * 1024) {
        print('Large PDF detected, using quick validation');
        return await _quickValidateByFilename(pdfFile);
      }
      
      // Read a larger portion for better analysis (128KB)
      final file = await pdfFile.open();
      final bytes = await file.read(128 * 1024); // 128KB for comprehensive analysis
      await file.close();
      
      int confidence = 0;
      bool hasStrongIndicator = false;
      
      // Strategy 1: Check PDF header and metadata
      final content = String.fromCharCodes(bytes);
      final lowerContent = content.toLowerCase();
      
      // Enhanced music metadata detection
      final musicMetadata = [
        'music', 'sheet', 'score', 'notation', 'musical', 'composition',
        'symphony', 'sonata', 'concerto', 'etude', 'prelude', 'fugue',
        'chord', 'scale', 'melody', 'harmony', 'rhythm', 'tempo',
        'key signature', 'time signature', 'bar', 'measure', 'beat',
        'piano', 'violin', 'guitar', 'orchestra', 'band', 'choir'
      ];
      
      int metadataMatches = 0;
      for (final term in musicMetadata) {
        if (lowerContent.contains(term)) {
          confidence += 10;
          metadataMatches++;
          print('Found music metadata: $term');
        }
      }
      
      // Bonus for multiple metadata matches
      if (metadataMatches >= 3) {
        confidence += 20;
        hasStrongIndicator = true;
        print('Multiple music metadata found - strong indicator');
      }
      
      // Strategy 2: Enhanced music software signatures
      final softwareSignatures = [
        'sibelius', 'finale', 'musescore', 'dorico', 'lilypond',
        'notion', 'overture', 'capella', 'forte', 'scorewriter',
        'encore', 'printmusic', 'harmony assistant', 'guitar pro'
      ];
      
      for (final signature in softwareSignatures) {
        if (lowerContent.contains(signature)) {
          confidence += 30;
          hasStrongIndicator = true;
          print('Found music software signature: $signature');
        }
      }
      
      // Strategy 3: Enhanced music symbols detection
      final musicSymbols = [
        '♪', '♫', '♬', '♭', '♯', '♮', // Basic symbols
        '𝄞', '𝄢', '𝄡', '𝄟', // Clefs
        '𝄐', '𝄑', '𝄒', '𝄓', // Time signatures
        '𝅝', '𝅗𝅥', '𝅘𝅥', '𝅘𝅥𝅮', '𝅘𝅥𝅯', // Note values
        '𝄽', '𝄾', '𝄿', '𝅀', '𝅁', '𝅂' // Rests
      ];
      
      int symbolCount = 0;
      for (final symbol in musicSymbols) {
        if (content.contains(symbol)) {
          confidence += 25;
          symbolCount++;
          hasStrongIndicator = true;
          print('Found music symbol: $symbol');
        }
      }
      
      // Strategy 4: Enhanced staff and notation keywords
      final staffKeywords = [
        'staff', 'stave', 'clef', 'treble', 'bass', 'alto', 'tenor',
        'measure', 'bar', 'note', 'rest', 'sharp', 'flat', 'natural',
        'key', 'time', 'signature', 'accidental', 'articulation'
      ];
      
      int staffMatches = 0;
      for (final keyword in staffKeywords) {
        if (lowerContent.contains(keyword)) {
          confidence += 12;
          staffMatches++;
          print('Found staff keyword: $keyword');
        }
      }
      
      // Bonus for multiple staff-related terms
      if (staffMatches >= 4) {
        confidence += 15;
        print('Multiple staff terms found');
      }
      
      // Strategy 5: Check for musical terms and expressions
      final musicalTerms = [
        'allegro', 'andante', 'adagio', 'largo', 'presto', 'moderato',
        'forte', 'piano', 'crescendo', 'diminuendo', 'legato', 'staccato',
        'ritardando', 'accelerando', 'fermata', 'da capo', 'dal segno',
        'coda', 'fine', 'repeat', 'volta', 'segno'
      ];
      
      int termMatches = 0;
      for (final term in musicalTerms) {
        if (lowerContent.contains(term)) {
          confidence += 8;
          termMatches++;
          print('Found musical term: $term');
        }
      }
      
      if (termMatches >= 3) {
        confidence += 12;
        print('Multiple musical terms found');
      }
      
      // Strategy 6: Enhanced image analysis for scanned music sheets
      final imageConfidence = await _analyzeImageContentEnhanced(bytes);
      confidence += imageConfidence;
      print('Enhanced image analysis confidence: $imageConfidence');
      
      // Strategy 7: Check for PDF structure patterns typical of music scores
      final structureConfidence = _analyzeDocumentStructure(content);
      confidence += structureConfidence;
      print('Document structure confidence: $structureConfidence');
      
      // Set strong indicator based on multiple factors
      if (imageConfidence >= 20 || structureConfidence >= 15 || 
          (imageConfidence >= 10 && structureConfidence >= 8)) {
        hasStrongIndicator = true;
        print('Strong indicator set from enhanced analysis');
      }
      
      print('Music content validation confidence score: $confidence');
      print('Has strong indicator: $hasStrongIndicator');
      
      // Multi-tier validation logic:
      // 1. Very high confidence (50+) - definitely music
      // 2. High confidence (35+) with strong indicators - likely music  
      // 3. Moderate confidence (25+) with multiple strong indicators - possibly music
      bool isValid = false;
      
      if (confidence >= 50) {
        isValid = true;
        print('Very high confidence validation passed');
      } else if (confidence >= 35 && hasStrongIndicator) {
        isValid = true;
        print('High confidence with strong indicators validation passed');
      } else if (confidence >= 25 && hasStrongIndicator && 
                 (imageConfidence >= 15 || structureConfidence >= 10)) {
        isValid = true;
        print('Moderate confidence with multiple indicators validation passed');
      }
      
      print('Final validation result: $isValid (confidence: $confidence, hasStrongIndicator: $hasStrongIndicator)');
      return isValid;
      
    } catch (e) {
      print('Error validating music content: $e');
      // If validation fails, be conservative and reject
      return false;
    }
  }
  
  /// Enhanced image content analysis for music-specific patterns
  Future<int> _analyzeImageContentEnhanced(Uint8List bytes) async {
    try {
      int confidence = 0;
      final content = String.fromCharCodes(bytes);
      final lowerContent = content.toLowerCase();
      
      // Count image references and types with better scoring
      final imagePatterns = ['/image', '/xobject', 'jpeg', 'jpg', 'png', 'tiff', 'bmp'];
      int imageCount = 0;
      for (final pattern in imagePatterns) {
        imageCount += pattern.allMatches(lowerContent).length;
      }
      
      if (imageCount > 0) {
        // Progressive scoring based on image density
        if (imageCount <= 3) {
          confidence += 8; // Few images
        } else if (imageCount <= 10) {
          confidence += 15; // Moderate image content
        } else if (imageCount <= 25) {
          confidence += 25; // High image density - likely scanned
        } else {
          confidence += 35; // Very high density - definitely scanned document
        }
        print('Found image content: $imageCount references (confidence: +${confidence})');
      }
      
      // Enhanced compression pattern detection
      final compressionPatterns = [
        'flatedecode', 'dctdecode', 'ccittfaxdecode', 'lzwdecode',
        'runlengthdecode', 'jbig2decode', 'jpxdecode'
      ];
      int compressionMatches = 0;
      for (final pattern in compressionPatterns) {
        if (lowerContent.contains(pattern)) {
          confidence += 6;
          compressionMatches++;
          print('Found compression pattern: $pattern');
        }
      }
      
      // Bonus for multiple compression types (typical of complex documents)
      if (compressionMatches >= 3) {
        confidence += 10;
        print('Multiple compression types found - complex document');
      }
      
      // Enhanced resolution detection
      final highResPatterns = [
        '300 dpi', '600 dpi', '1200 dpi', '2400 dpi',
        '/width 1200', '/width 1800', '/width 2400', '/width 3600',
        '/height 1600', '/height 2400', '/height 3200'
      ];
      
      int resolutionMatches = 0;
      for (final pattern in highResPatterns) {
        if (lowerContent.contains(pattern)) {
          confidence += 8;
          resolutionMatches++;
          print('Found high-resolution indicator: $pattern');
        }
      }
      
      // Enhanced grayscale/monochrome detection (typical of sheet music)
      final colorSpacePatterns = [
        'devicegray', 'devicecmyk', '/gray', 'grayscale',
        'monochrome', 'blackandwhite', '/bitspercomponent 1'
      ];
      
      int colorSpaceMatches = 0;
      for (final pattern in colorSpacePatterns) {
        if (lowerContent.contains(pattern)) {
          confidence += 7;
          colorSpaceMatches++;
          print('Found grayscale/monochrome pattern: $pattern');
        }
      }
      
      // Check for document structure typical of sheet music
      final structuralPatterns = [
        '/pages', '/page', '/contents', '/resources',
        '/font', '/fontdescriptor', '/encoding'
      ];
      
      int structuralMatches = 0;
      for (final pattern in structuralPatterns) {
        structuralMatches += pattern.allMatches(lowerContent).length;
      }
      
      // Multiple pages with consistent structure suggests sheet music
      if (structuralMatches > 10) {
        confidence += 12;
        print('Complex document structure detected');
      }
      
      // Advanced pattern detection for scanned music sheets
      confidence += _detectStaffLinePatterns(bytes);
      confidence += _detectMusicSymbolPatterns(bytes);
      
      // Check for OCR-related patterns (common in scanned documents)
      final ocrPatterns = ['ocr', 'text recognition', 'scanned', 'digitized'];
      for (final pattern in ocrPatterns) {
        if (lowerContent.contains(pattern)) {
          confidence += 10;
          print('Found OCR/scanning indicator: $pattern');
        }
      }
      
      return confidence;
    } catch (e) {
      print('Error analyzing enhanced image content: $e');
      return 0;
    }
  }
  
  /// Analyze document structure for music score patterns
  int _analyzeDocumentStructure(String content) {
    try {
      int confidence = 0;
      final lowerContent = content.toLowerCase();
      
      // Check for multi-page structure (typical of sheet music)
      final pageCount = '/page'.allMatches(lowerContent).length;
      if (pageCount > 1) {
        confidence += math.min(pageCount * 3, 15); // Max 15 points for pages
        print('Multi-page document detected: $pageCount pages');
      }
      
      // Check for font patterns typical of music notation
      final musicFontPatterns = [
        'bravura', 'emmentaler', 'gonville', 'lilyjazz', 'feta',
        'musicology', 'opus', 'petrucci', 'sebastian', 'sonora'
      ];
      
      for (final font in musicFontPatterns) {
        if (lowerContent.contains(font)) {
          confidence += 20;
          print('Found music notation font: $font');
        }
      }
      
      // Check for vector graphics patterns (common in digital scores)
      final vectorPatterns = [
        '/path', '/moveto', '/lineto', '/curveto', '/closepath',
        'bezier', 'spline', 'vector'
      ];
      
      int vectorMatches = 0;
      for (final pattern in vectorPatterns) {
        vectorMatches += pattern.allMatches(lowerContent).length;
      }
      
      if (vectorMatches > 20) {
        confidence += 15;
        print('Complex vector graphics detected - likely digital score');
      }
      
      // Check for metadata patterns
      final metadataPatterns = [
        '/title', '/subject', '/author', '/creator', '/producer',
        '/creationdate', '/moddate', '/keywords'
      ];
      
      int metadataCount = 0;
      for (final pattern in metadataPatterns) {
        if (lowerContent.contains(pattern)) {
          metadataCount++;
        }
      }
      
      if (metadataCount >= 4) {
        confidence += 8;
        print('Rich metadata found - professional document');
      }
      
      return confidence;
    } catch (e) {
      print('Error analyzing document structure: $e');
      return 0;
    }
  }

  /// Detect staff line patterns in binary data
  int _detectStaffLinePatterns(Uint8List bytes) {
    try {
      int confidence = 0;
      
      // Look for repeated horizontal line patterns (staff lines)
      // Staff lines typically appear as repeated byte sequences
      final patterns = <List<int>>[
        [0xFF, 0xFF, 0xFF], // White lines
        [0x00, 0x00, 0x00], // Black lines
        [0xFF, 0x00, 0xFF], // Alternating patterns
      ];
      
      for (final pattern in patterns) {
        int patternCount = 0;
        for (int i = 0; i <= bytes.length - pattern.length; i++) {
          bool matches = true;
          for (int j = 0; j < pattern.length; j++) {
            if (bytes[i + j] != pattern[j]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            patternCount++;
          }
        }
        
        if (patternCount > 20) { // Threshold for staff line detection
          confidence += 15;
          print('Detected potential staff line patterns: $patternCount occurrences');
          break; // Don't double-count
        }
      }
      
      // Look for regular spacing patterns (typical of staff lines)
      final spacingPatterns = _analyzeByteSpacing(bytes);
      if (spacingPatterns > 10) {
        confidence += 10;
        print('Detected regular spacing patterns: $spacingPatterns');
      }
      
      return confidence;
    } catch (e) {
      print('Error detecting staff line patterns: $e');
      return 0;
    }
  }

  /// Detect music symbol patterns in binary data
  int _detectMusicSymbolPatterns(Uint8List bytes) {
    try {
      int confidence = 0;
      
      // Look for circular patterns (note heads)
      final circularPatterns = _detectCircularPatterns(bytes);
      if (circularPatterns > 5) {
        confidence += 12;
        print('Detected potential note head patterns: $circularPatterns');
      }
      
      // Look for vertical line patterns (stems, bar lines)
      final verticalPatterns = _detectVerticalPatterns(bytes);
      if (verticalPatterns > 8) {
        confidence += 8;
        print('Detected vertical line patterns: $verticalPatterns');
      }
      
      // Look for curved patterns (slurs, ties)
      final curvedPatterns = _detectCurvedPatterns(bytes);
      if (curvedPatterns > 3) {
        confidence += 6;
        print('Detected curved patterns: $curvedPatterns');
      }
      
      return confidence;
    } catch (e) {
      print('Error detecting music symbol patterns: $e');
      return 0;
    }
  }

  /// Analyze byte spacing for regular patterns
  int _analyzeByteSpacing(Uint8List bytes) {
    try {
      int regularSpacingCount = 0;
      final spacingMap = <int, int>{};
      
      // Sample every 100th byte to find spacing patterns
      for (int i = 0; i < bytes.length - 100; i += 100) {
        final spacing = bytes[i + 100] - bytes[i];
        spacingMap[spacing] = (spacingMap[spacing] ?? 0) + 1;
      }
      
      // Count spacings that occur frequently (indicating regular patterns)
      for (final count in spacingMap.values) {
        if (count > 5) {
          regularSpacingCount += count;
        }
      }
      
      return regularSpacingCount;
    } catch (e) {
      return 0;
    }
  }

  /// Detect circular patterns that might be note heads
  int _detectCircularPatterns(Uint8List bytes) {
    try {
      int circularCount = 0;
      
      // Look for byte sequences that might represent circular shapes
      // This is a simplified heuristic based on common image encoding patterns
      for (int i = 0; i < bytes.length - 8; i++) {
        // Look for patterns that might indicate filled circles
        if (bytes[i] == 0x00 && bytes[i + 1] == 0xFF && 
            bytes[i + 2] == 0xFF && bytes[i + 3] == 0x00) {
          circularCount++;
        }
        // Look for patterns that might indicate hollow circles
        if (bytes[i] == 0xFF && bytes[i + 1] == 0x00 && 
            bytes[i + 2] == 0x00 && bytes[i + 3] == 0xFF) {
          circularCount++;
        }
      }
      
      return circularCount;
    } catch (e) {
      return 0;
    }
  }

  /// Detect vertical line patterns
  int _detectVerticalPatterns(Uint8List bytes) {
    try {
      int verticalCount = 0;
      
      // Look for repeated vertical byte patterns
      for (int i = 0; i < bytes.length - 16; i += 4) {
        bool isVerticalPattern = true;
        final baseValue = bytes[i];
        
        // Check if next few bytes have similar values (vertical line)
        for (int j = 1; j < 16 && i + j < bytes.length; j++) {
          if ((bytes[i + j] - baseValue).abs() > 50) {
            isVerticalPattern = false;
            break;
          }
        }
        
        if (isVerticalPattern) {
          verticalCount++;
        }
      }
      
      return verticalCount;
    } catch (e) {
      return 0;
    }
  }

  /// Detect curved patterns that might be slurs or ties
  int _detectCurvedPatterns(Uint8List bytes) {
    try {
      int curvedCount = 0;
      
      // Look for gradual changes in byte values (curves)
      for (int i = 0; i < bytes.length - 12; i += 3) {
        bool isCurvedPattern = true;
        int direction = 0;
        
        for (int j = 1; j < 12 && i + j < bytes.length; j++) {
          final diff = bytes[i + j] - bytes[i + j - 1];
          if (j == 1) {
            direction = diff > 0 ? 1 : -1;
          } else {
            // Check if the pattern continues in a curved manner
            final currentDirection = diff > 0 ? 1 : -1;
            if (currentDirection != direction && diff.abs() > 10) {
              // Direction change might indicate a curve
              curvedCount++;
              break;
            }
          }
        }
      }
      
      return curvedCount;
    } catch (e) {
      return 0;
    }
  }
  
  /// Quick validation based on filename and basic checks
  Future<bool> _quickValidateByFilename(File pdfFile) async {
    try {
      final filename = pdfFile.path.toLowerCase();
      
      // Check filename for music-related terms
      final musicTerms = [
        'music', 'sheet', 'score', 'song', 'symphony', 'sonata',
        'concerto', 'etude', 'prelude', 'fugue', 'chord', 'scale'
      ];
      
      for (final term in musicTerms) {
        if (filename.contains(term)) {
          print('Found music term in filename: $term');
          return true;
        }
      }
      
      // For large files without obvious music indicators, be conservative
      print('Large PDF without clear music indicators in filename');
      return false;
      
    } catch (e) {
      print('Error in quick validation: $e');
      return false;
    }
  }

  /// Test connection to the Flask server
  Future<void> _testServerConnection() async {
    await _checkServerStatus(showSnack: true);
  }

  /// Check server status (used on init and periodic). Optionally show snack.
  Future<void> _checkServerStatus({bool showSnack = false}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_serverUrl/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 25));
      final online = response.statusCode == 200;
      setState(() {
        _serverOnline = online;
        _serverStatusMessage = online ? 'Online' : 'Offline';
      });
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(online
                ? 'Server is online.'
                : 'Server responded with status: ${response.statusCode}\nResponse: ${response.body}'),
            backgroundColor: online ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _serverOnline = false;
        _serverStatusMessage = 'Offline';
      });
      if (showSnack && mounted) {
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _serverOnline ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _serverOnline ? 'Online' : 'Offline',
                  style: const TextStyle(color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Test Server',
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _testServerConnection,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _convertedItems.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: (_isConverting || _isPickingFile) ? null : _pickPdfFile,
              backgroundColor: _brandPrimary,
              foregroundColor: Color(0xFFF5F5DD),
              icon: (_isConverting || _isPickingFile)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFF5F5DD),
                      ),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isPickingFile ? 'Opening a File...' : _isConverting ? 'Converting...' : 'Upload PDF'),
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
                              onPressed: (_isConverting || _isPickingFile) ? null : _pickPdfFile,
                              icon: (_isConverting || _isPickingFile)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFF5F5DD),
                                      ),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(_isPickingFile ? 'Opening File...' : _isConverting ? 'Converting...' : 'Upload PDF'),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                                itemCount: _convertedItems.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = _convertedItems[index];
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _brandPrimary.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(12),
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
                                              icon: _isOpeningFile
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Color(0xFF8B4511),
                                                      ),
                                                    )
                                                  : const Icon(Icons.open_in_new),
                                              color: _brandAccent,
                                              tooltip: _isOpeningFile ? 'Opening...' : 'Open',
                                              onPressed: _isOpeningFile ? null : () => _openMusicSheet(item['path'] ?? '', item['name'] ?? ''),
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
              // Full screen overlay with blur effect
              Container(
                color: Colors.black.withOpacity(0.4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated circular progress with rotating dots
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Stack(
                          children: [
                            // Background circle
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _brandPrimary.withOpacity(0.2),
                                  width: 3,
                                ),
                              ),
                            ),
                            // Animated progress arc
                            AnimatedBuilder(
                              animation: _loaderController,
                              builder: (context, _) {
                                return CustomPaint(
                                  size: const Size(80, 80),
                                  painter: _CircularProgressPainter(
                                    progress: _loaderController.value,
                                    color: _brandPrimary,
                                  ),
                                );
                              },
                            ),
                            // Center icon
                            Center(
                              child: AnimatedBuilder(
                                animation: _loaderController,
                                builder: (context, _) {
                                  return Transform.rotate(
                                    angle: _loaderController.value * 2 * math.pi,
                                    child: Icon(
                                      Icons.music_note,
                                      size: 32,
                                      color: _brandPrimary,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Animated equalizer bars
                      SizedBox(
                        width: 120,
                        height: 40,
                        child: AnimatedBuilder(
                          animation: _loaderController,
                          builder: (context, _) {
                            final phases = [0.0, 0.2, 0.4, 0.6, 0.8];
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(phases.length, (i) {
                                final t = (_loaderController.value + phases[i]) % 1.0;
                                final h = 8 + 32 * (0.5 + 0.5 * math.sin(2 * math.pi * t));
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  width: 12,
                                  height: h,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        _brandPrimary,
                                        _brandPrimary.withOpacity(0.6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _brandPrimary.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                       const SizedBox(height: 32),
                      
                      // Status text
                      Text(
                        'Validating & Converting PDF to Music',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _brandAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_currentConvertingName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _brandPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _currentConvertingName!,
                            style: TextStyle(
                              fontSize: 14,
                              color: _brandPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Please wait while we process your sheet music...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_isOpeningFile) ...[
              // Full screen overlay with blur effect for file opening
              Container(
                color: Colors.black.withOpacity(0.4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated circular progress with rotating icon
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Stack(
                          children: [
                            // Background circle
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _brandPrimary.withOpacity(0.2),
                                  width: 3,
                                ),
                              ),
                            ),
                            // Animated progress arc
                            AnimatedBuilder(
                              animation: _loaderController,
                              builder: (context, _) {
                                return CustomPaint(
                                  size: const Size(80, 80),
                                  painter: _CircularProgressPainter(
                                    progress: _loaderController.value,
                                    color: _brandPrimary,
                                  ),
                                );
                              },
                            ),
                            // Center icon
                            Center(
                              child: AnimatedBuilder(
                                animation: _loaderController,
                                builder: (context, _) {
                                  return Transform.rotate(
                                    angle: _loaderController.value * 2 * math.pi,
                                    child: Icon(
                                      Icons.open_in_new,
                                      size: 32,
                                      color: _brandPrimary,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Status text
                      Text(
                        'Opening Music Sheet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _brandAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please wait...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
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

// Custom painter for circular progress animation
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CircularProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      2 * math.pi * progress, // Progress angle
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
