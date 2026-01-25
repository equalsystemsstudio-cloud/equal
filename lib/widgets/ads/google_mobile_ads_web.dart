import 'package:flutter/material.dart';

// Minimal stub for AdWidget to satisfy web builds
class AdWidget extends StatelessWidget {
  final dynamic ad;
  const AdWidget({Key? key, required this.ad}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Text('Ad Placeholder'),
      ),
    );
  }
}