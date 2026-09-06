// Minimal host app. The real platform coverage lives in integration_test/.
import 'package:flutter/material.dart';
import 'package:keybay/keybay.dart';

void main() => runApp(const _HarnessApp());

class _HarnessApp extends StatelessWidget {
  const _HarnessApp();

  Future<String> _open() async {
    final session = await Keybay.open();
    try {
      return session.wasInitialized
          ? 'Keybay store initialized'
          : 'Keybay store opened';
    } finally {
      await session.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('keybay harness')),
        body: Center(
          child: FutureBuilder<String>(
            future: _open(),
            builder: (context, snap) => Text(
              snap.hasError
                  ? 'Keybay error:\n${snap.error}'
                  : (snap.data ?? 'opening…'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
