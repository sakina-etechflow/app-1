import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/processing_service.dart';
import '../state/app_state.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final appState = context.read<AppState>();
    final doc = appState.doc;
    final path = appState.normalizedPhotoPath;
    if (doc == null || path == null) {
      setState(() => _error = 'Missing photo or document.');
      return;
    }
    try {
      final result = await ProcessingService().run(
        rawPhotoPath: path,
        doc: doc,
        wearsGlasses: appState.wearsGlasses,
      );
      if (!mounted) return;
      appState.setResult(
        report: result.report,
        clean: result.cleanJpg,
        preview: result.previewJpg,
      );
      Navigator.pushReplacementNamed(context, '/results');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not process the photo:\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Analyzing on your device…',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  Text('Face, framing, background, lighting',
                      style: TextStyle(color: Colors.black54)),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, '/capture'),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
