import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../utils/supabase_auth_debug.dart';
import '../utils/debug_supabase.dart';
import '../services/localization_service.dart';

class DebugAuthScreen extends StatefulWidget {
  const DebugAuthScreen({super.key});

  @override
  State<DebugAuthScreen> createState() => _DebugAuthScreenState();
}

class _DebugAuthScreenState extends State<DebugAuthScreen> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _diagnosticsResults;
  Map<String, dynamic>? _updateResults;
  bool _isLoading = false;

  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final profile = await _authService.getCurrentUserProfile();
      if (profile != null) {
        _displayNameController.text = profile['display_name'] ?? '';
        _bioController.text = profile['bio'] ?? '';
      }
    } catch (e) {
      if (kDebugMode) debugPrint(('Error loading profile: $e').toString());
    }
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
      _diagnosticsResults = null;
    });

    try {
      final results = await SupabaseAuthDebug.runFullDiagnostics();
      setState(() {
        _diagnosticsResults = results;
      });
    } catch (e) {
      setState(() {
        _diagnosticsResults = {'error': e.toString()};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testProfileUpdate() async {
    setState(() {
      _isLoading = true;
      _updateResults = null;
    });

    try {
      final updates = <String, dynamic>{};

      if (_displayNameController.text.isNotEmpty) {
        updates['display_name'] = _displayNameController.text;
      }

      if (_bioController.text.isNotEmpty) {
        updates['bio'] = _bioController.text;
      }

      if (updates.isEmpty) {
        updates['updated_at'] = DateTime.now().toIso8601String();
      }

      // Test with debug utility
      final debugResults = await SupabaseAuthDebug.debugProfileUpdate(updates);

      // Also test with auth service
      try {
        await _authService.updateProfile(
          fullName: _displayNameController.text.isNotEmpty
              ? _displayNameController.text
              : null,
          bio: _bioController.text.isNotEmpty ? _bioController.text : null,
        );
        debugResults['auth_service_update'] = 'SUCCESS';
      } catch (e) {
        debugResults['auth_service_update'] = 'FAILED: $e';
      }

      setState(() {
        _updateResults = debugResults;
      });
    } catch (e) {
      setState(() {
        _updateResults = {'error': e.toString()};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const LocalizedText('Supabase Auth Debug'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Diagnostics Section
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocalizationService.t('Authentication Diagnostics'),
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _runDiagnostics,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const LocalizedText('Run Full Diagnostics'),
                    ),
                    if (_diagnosticsResults != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        LocalizationService.t('Results:'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[600]!),
                        ),
                        child: Text(
                          _formatResults(_diagnosticsResults!),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Profile Update Test Section
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocalizationService.t('Profile Update Test'),
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _displayNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: LocalizationService.t('Display Name'),
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bioController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: LocalizationService.t('Bio'),
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _testProfileUpdate,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const LocalizedText('Test Profile Update'),
                    ),
                    if (_updateResults != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        LocalizationService.t('Update Results:'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _updateResults!['update_success'] == true
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _updateResults!['update_success'] == true
                                ? Colors.green[300]!
                                : Colors.red[300]!,
                          ),
                        ),
                        child: Text(
                          _formatResults(_updateResults!),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: _updateResults!['update_success'] == true
                                ? Colors.green[300]
                                : Colors.red[300],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quick Actions
            Card(
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocalizationService.t('Quick Actions'),
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final result =
                                        await SupabaseAuthDebug.debugSession();
                                    if (mounted) {
                                      _showResultDialog(
                                        'Session Debug',
                                        result,
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showResultDialog('Session Debug Error', {
                                        'error': e.toString(),
                                      });
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          child: const LocalizedText('Check Session'),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final result =
                                        await SupabaseAuthDebug.testRLSPolicies();
                                    if (mounted) {
                                      _showResultDialog(
                                        'RLS Policies Test',
                                        result,
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showResultDialog('RLS Test Error', {
                                        'error': e.toString(),
                                      });
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          child: const LocalizedText('Test RLS'),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final result =
                                        await SupabaseAuthDebug.testDatabaseConnection();
                                    if (mounted) {
                                      _showResultDialog(
                                        'Database Connection',
                                        result,
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showResultDialog('Database Test Error', {
                                        'error': e.toString(),
                                      });
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          child: const LocalizedText('Test DB'),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final success =
                                        await SupabaseAuthDebug.validateAndRefreshSession();
                                    if (mounted) {
                                      _showResultDialog('Session Validation', {
                                        'success': success,
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showResultDialog(
                                        'Session Validation Error',
                                        {'error': e.toString()},
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          child: const LocalizedText('Refresh Session'),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  setState(() => _isLoading = true);
                                  try {
                                    final result =
                                        await SupabaseDebugger.runDiagnostics();
                                    SupabaseDebugger.printResults(result);
                                    if (mounted) {
                                      _showResultDialog(
                                        'Comprehensive Test',
                                        result,
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showResultDialog(
                                        'Full System Test Error',
                                        {
                                          'error': e.toString(),
                                          'message':
                                              'The comprehensive test encountered an error. This might be due to missing dependencies or configuration issues.',
                                        },
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isLoading = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                          child: const LocalizedText('Full System Test'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResultDialog(String title, Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(title),
        content: SingleChildScrollView(
          child: Text(
            _formatResults(result),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LocalizedText('close'),
          ),
        ],
      ),
    );
  }

  String _formatResults(Map<String, dynamic> results) {
    final buffer = StringBuffer();

    void formatValue(String key, dynamic value, [int indent = 0]) {
      final prefix = '  ' * indent;

      if (value is Map<String, dynamic>) {
        buffer.writeln('$prefix$key:');
        value.forEach((k, v) => formatValue(k, v, indent + 1));
      } else if (value is List) {
        buffer.writeln('$prefix$key: [${value.length} items]');
        for (int i = 0; i < value.length && i < 3; i++) {
          formatValue('[$i]', value[i], indent + 1);
        }
        if (value.length > 3) {
          buffer.writeln('$prefix  ... and ${value.length - 3} more');
        }
      } else {
        buffer.writeln('$prefix$key: $value');
      }
    }

    results.forEach((key, value) => formatValue(key, value));
    return buffer.toString();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }
}
