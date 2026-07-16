import 'dart:io';

import 'package:camera/camera.dart';
import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/live_coach.dart';
import '../state/app_state.dart';
import '../widgets/oval_overlay.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  CameraDescription? _camera;
  String? _cameraError;
  bool _busy = false;

  // Live coaching state.
  final LiveCoach _coach = LiveCoach();
  CoachStatus _status = CoachStatus.searching;
  bool _autoCapture = true;
  DateTime? _readySince;

  /// How long every check must hold before auto-capture fires.
  static const _autoHold = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 // single-plane, what ML Kit wants
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _camera = front;
      });
      await controller.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError =
          'Camera unavailable ($e).\nYou can import a photo instead.');
    }
  }

  Future<void> _onFrame(CameraImage frame) async {
    final c = _controller;
    final cam = _camera;
    if (c == null || cam == null || _busy || !mounted) return;
    final status =
        await _coach.analyse(frame, cam, c.value.deviceOrientation);
    if (status == null || !mounted || _busy) return;

    // Track how long we have been continuously ready.
    if (status.ready) {
      _readySince ??= DateTime.now();
    } else {
      _readySince = null;
    }
    setState(() => _status = status);

    if (_autoCapture &&
        _readySince != null &&
        DateTime.now().difference(_readySince!) >= _autoHold) {
      _readySince = null;
      await _capture();
    }
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    if (c != null) {
      // Stop the stream before disposing to avoid buffer callbacks after close.
      Future(() async {
        try {
          if (c.value.isStreamingImages) await c.stopImageStream();
        } catch (_) {}
        await c.dispose();
      });
    }
    _coach.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      _goProcess(file.path);
    } catch (e) {
      _snack('Could not take the photo: $e');
      if (mounted) {
        setState(() => _busy = false);
        // Resume coaching after a failed capture.
        try {
          if (!c.value.isStreamingImages) await c.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery);
      if (x == null) {
        setState(() => _busy = false);
        return;
      }
      _goProcess(x.path);
    } catch (e) {
      _snack('Could not import: $e');
      setState(() => _busy = false);
    }
  }

  void _goProcess(String path) {
    if (!mounted) return;
    context.read<AppState>().setNormalizedPhoto(path);
    Navigator.pushReplacementNamed(context, '/processing');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final doc = appState.doc;
    final askGlasses =
        doc != null && doc.glassesRule != GlassesRule.allowedNoGlare;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(doc?.displayName ?? 'Capture'),
        actions: [
          Row(
            children: [
              const Text('Auto',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Switch(
                value: _autoCapture,
                onChanged: (v) => setState(() {
                  _autoCapture = v;
                  _readySince = null;
                }),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _preview()),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              children: [
                if (askGlasses)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('I am wearing glasses',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      doc.glassesRule == GlassesRule.banned
                          ? 'Glasses are not allowed for this document.'
                          : 'Glasses are discouraged for this document.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    value: appState.wearsGlasses,
                    onChanged: (v) =>
                        context.read<AppState>().setWearsGlasses(v),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _busy ? null : _import,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Import'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed:
                            (_controller != null && !_busy) ? _capture : null,
                        icon: const Icon(Icons.camera_alt),
                        label: Text(_busy ? 'Working…' : 'Capture'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.previewSize?.height ?? 1,
            height: c.value.previewSize?.width ?? 1,
            child: CameraPreview(c),
          ),
        ),
        OvalOverlay(ready: _status.ready),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _status.ready
                  ? const Color(0xCC2E7D32)
                  : Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _status.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
