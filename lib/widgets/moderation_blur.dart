import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ModerationBlur extends StatelessWidget {
  const ModerationBlur({
    super.key,
    required this.child,
    required this.contentRating,
    required this.blurPreview,
    required this.onReveal,
  });

  final Widget child;
  final String contentRating; // safe | sensitive | adult | banned
  final bool blurPreview;
  final VoidCallback onReveal;

  bool get _shouldBlock => contentRating == 'banned';
  bool get _shouldBlur => blurPreview &&
      (contentRating == 'sensitive' || contentRating == 'adult');

  @override
  Widget build(BuildContext context) {
    if (_shouldBlock) {
      return Center(
        child: Text(
          'Content unavailable',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      );
    }
    if (!_shouldBlur) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  'Sensitive content',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onReveal,
                child: const Text('View'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
