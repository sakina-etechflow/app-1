import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/processing_service.dart';
import '../state/app_state.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

enum _View { working, noFace, error }

class _ProcessingScreenState extends State<ProcessingScreen> {
  final CancelToken _cancel = CancelToken();
  _View _view = _View.working;
  ProcessingStage _stage = ProcessingStage.normalizing;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    // If the screen goes away mid-run, stop the pipeline cooperatively.
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final appState = context.read<AppState>();
    final doc = appState.doc;
    final path = appState.normalizedPhotoPath;
    if (doc == null || path == null) {
      setState(() {
        _view = _View.error;
        _error = 'Missing photo or document.';
      });
      return;
    }
    try {
      final result = await ProcessingService().run(
        rawPhotoPath: path,
        doc: doc,
        wearsGlasses: appState.wearsGlasses,
        cancelToken: _cancel,
        onStage: (s) {
          if (mounted && !_cancel.isCancelled) setState(() => _stage = s);
        },
      );
      if (!mounted || _cancel.isCancelled) return;
      appState.setResult(
        report: result.report,
        clean: result.cleanJpg,
        preview: result.previewJpg,
      );
      Navigator.pushReplacementNamed(context, '/results');
    } on ProcessingCancelled {
      // User cancelled: the screen is (or is about to be) gone; do nothing.
      return;
    } on NoFaceDetected {
      if (!mounted) return;
      setState(() => _view = _View.noFace);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _view = _View.error;
        _error = 'Could not process the photo:\n$e';
      });
    }
  }

  void _cancelAndBack() {
    _cancel.cancel();
    Navigator.pushReplacementNamed(context, '/capture');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_view) {
            _View.working => _workingView(),
            _View.noFace => _noFaceView(),
            _View.error => _errorView(),
          },
        ),
      ),
    );
  }

  Widget _workingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        SizedBox(
          width: 220,
          child: Column(
            children: [
              // Determinate bar tracking the pipeline stage.
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _stage.fraction,
                  minHeight: 8,
                  backgroundColor: Colors.black12,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _stage.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'On your device — nothing is uploaded',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _cancelAndBack,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _noFaceView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.face_retouching_off_outlined,
              color: Colors.orange, size: 44),
          const SizedBox(height: 14),
          const Text(
            'No face detected',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'We couldn\'t find a clear, front-facing face in this photo. '
            'Make sure your whole head is in frame, well lit, and facing the '
            'camera, then try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/capture'),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Retake photo'),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/capture'),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
