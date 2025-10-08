import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Global service to manage server connection status
/// This service persists across screen navigation to maintain connection
class ServerConnectionService {
  static final ServerConnectionService _instance = ServerConnectionService._internal();
  factory ServerConnectionService() => _instance;
  ServerConnectionService._internal();

  // Server configuration
  static const String _localServerUrl = 'http://192.168.1.8:5000';
  static const String _onlineServerUrl = 'https://pdf-to-musicxml-converter.onrender.com';
  static const String _serverUrl = _onlineServerUrl;

  // Connection state
  bool _serverOnline = false;
  String? _serverStatusMessage;
  Timer? _serverStatusTimer;
  bool _isInitialized = false;

  // Stream controller for broadcasting connection status changes
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();
  final StreamController<String?> _statusMessageController = StreamController<String?>.broadcast();

  // Getters
  bool get isConnected => _serverOnline;
  String? get currentStatusMessage => _serverStatusMessage;
  String get serverUrl => _serverUrl;
  
  // Streams for listening to connection changes
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  Stream<String?> get statusMessage => _statusMessageController.stream;

  /// Initialize the service and start periodic connection checks
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isInitialized = true;
    
    // Initial server status check
    await _checkServerStatus();
    
    // Start periodic status checks every 60 seconds
    _serverStatusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkServerStatus();
    });
  }

  /// Check server status and update connection state
  Future<void> _checkServerStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_serverUrl/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 25));
      
      final online = response.statusCode == 200;
      _updateConnectionStatus(online, online ? 'Online' : 'Offline');
      
    } catch (e) {
      _updateConnectionStatus(false, 'Offline');
    }
  }

  /// Update connection status and notify listeners
  void _updateConnectionStatus(bool online, String message) {
    if (_serverOnline != online || _serverStatusMessage != message) {
      _serverOnline = online;
      _serverStatusMessage = message;
      
      // Broadcast the changes to all listeners
      _connectionStatusController.add(_serverOnline);
      _statusMessageController.add(_serverStatusMessage);
    }
  }

  /// Manually trigger a server status check
  Future<void> checkServerStatus({bool showSnack = false, BuildContext? context}) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_serverUrl/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 25));
      
      final online = response.statusCode == 200;
      _updateConnectionStatus(online, online ? 'Online' : 'Offline');
      
      if (showSnack && context != null && context.mounted) {
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
      _updateConnectionStatus(false, 'Offline');
      
      if (showSnack && context != null && context.mounted) {
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

  /// Ensure server is available with retry logic
  Future<bool> ensureServerAvailableWithRetry() async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final resp = await http
            .get(
              Uri.parse('$_serverUrl/health'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 25));
        
        if (resp.statusCode == 200) {
          _updateConnectionStatus(true, 'Online');
          return true;
        }
        
        throw Exception('Server health check failed: ${resp.statusCode}');
      } catch (e) {
        if (attempt == 2) {
          _updateConnectionStatus(false, 'Offline');
          return false;
        }
        // Small delay before retry
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return false;
  }

  /// Dispose of the service (should only be called when app is closing)
  void dispose() {
    _serverStatusTimer?.cancel();
    _connectionStatusController.close();
    _statusMessageController.close();
    _isInitialized = false;
  }
}