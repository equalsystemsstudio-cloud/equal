import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/safe_mode_service.dart';

class SafeModeScreen extends StatefulWidget {
  const SafeModeScreen({super.key});

  @override
  State<SafeModeScreen> createState() => _SafeModeScreenState();
}

class _SafeModeScreenState extends State<SafeModeScreen> {
  final SafeModeService _service = SafeModeService();
  bool _loading = true;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _service.getSafeMode();
    if (!mounted) return;
    setState(() {
      _enabled = v;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    final ok = await _service.setSafeMode(value);
    if (!mounted) return;
    final msg = ok ? 'Safe Mode updated' : 'Failed to update Safe Mode';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Safety Settings',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe Mode',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hide adult content and blur sensitive media by default.',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _enabled,
                    onChanged: _toggle,
                    title: Text(
                      _enabled ? 'Enabled' : 'Disabled',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text('Recommended for all users'),
                  ),
                ],
              ),
            ),
    );
  }
}

