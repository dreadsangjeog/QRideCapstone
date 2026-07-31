import 'package:flutter/material.dart';

/// Shown when [Supabase.initialize] or config checks fail.
class QRideBootstrapError extends StatelessWidget {
  const QRideBootstrapError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SelectableText(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
