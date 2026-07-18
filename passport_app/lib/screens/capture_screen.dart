import 'dart:io';
import 'dart:math' as math;

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
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.front;
  String? _cameraError;
  bool _permissionDenied = false;
  bool _busy = false;

  // Live coaching state.
  final LiveCoach _coach = LiveCoach();
  CoachStatus _status = CoachStatus.searching;
  bool _autoCapture = true;
  DateTime? _readySince;

  // Low-light warning state (S3): estimated from the frame luminance.
  bool _lowLight = false;
  DateTime _lastLum = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long every check must hold before auto-capture fires.
  static const _autoHold = Duration(milliseconds: 1200);

  /// Luminance is sampled at most this often (independent of the coach).
  static const _lumInterval = Duration(milliseconds: 500);

  /// Average Y below this reads as too dark; hysteresis avoids flicker.
  static const _lumEnter = 68.0; // becomes "low light" below this
  static const _lumExit = 82.0; // clears the warning above this

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera({CameraLensDirection? prefer}) async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        throw CameraException('noCamera', 'No cameras found on this device.');
      }
      final want = prefer ?? _lens;
      final selected = _cameras.firstWhere(
        (c) => c.lensDirection == want,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        selected,
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
        _camera = selected;
        _lens = selected.lensDirection;
        _cameraError = null;
        _permissionDenied = false;
        _lowLight = false;
        _status = CoachStatus.searching;
        _readySince = null;
      });
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      final denied =
          code.contains('denied') || code.contains('permission');
      setState(() {
        if (denied) {
          _permissionDenied = true;
        } else {
          _cameraError =
              'Camera unavailable (${e.description ?? e.code}).\nYou can import a photo instead.';
        }
      });
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

    _updateLowLight(frame);

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

  /// Cheap brightness estimate from the frame's luminance plane. On Android
  /// NV21 the first width*height bytes are the Y (luma) channel; on iOS BGRA
  /// we fall back to sampling the packed bytes, which still tracks brightness.
  void _updateLowLight(CameraImage frame) {
    final now = DateTime.now();
    if (now.difference(_lastLum) < _lumInterval) return;
    _lastLum = now;
    if (frame.planes.isEmpty) return;
    final bytes = frame.planes.first.bytes;
    if (bytes.isEmpty) return;

    // On Android the luma region is the first width*height bytes; elsewhere
    // sample the whole first plane.
    final lumaLen = Platform.isAndroid
        ? math.min(frame.width * frame.height, bytes.length)
        : bytes.length;
    const samples = 2000;
    final step = math.max(1, lumaLen ~/ samples);
    int sum = 0, n = 0;
    for (var i = 0; i < lumaLen; i += step) {
      sum += bytes[i];
      n++;
    }
    if (n == 0) return;
    final avg = sum / n;

    // Hysteresis so the banner doesn't flicker around the threshold.
    final low = _lowLight ? avg < _lumExit : avg < _lumEnter;
    if (low != _lowLight && mounted) {
      setState(() => _lowLight = low);
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

  bool get _canFlip =>
      _cameras.where((c) => c.lensDirection == CameraLensDirection.front).isNotEmpty &&
      _cameras.where((c) => c.lensDirection == CameraLensDirection.back).isNotEmpty;

  Future<void> _flip() async {
    if (_busy) return;
    final next = _lens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    setState(() => _busy = true);
    final old = _controller;
    _controller = null;
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
    }
    await _initCamera(prefer: next);
    if (mounted) setState(() => _busy = false);
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
      // Uses the system Photo Picker (Android Photo Picker / PHPicker); no
      // broad media permission is requested.
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
                    if (_canFlip) ...[
                      _CircleControl(
                        icon: Icons.cameraswitch_outlined,
                        tooltip: 'Flip camera',
                        onPressed: _busy ? null : _flip,
                      ),
                      const SizedBox(width: 12),
                    ],
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
    if (_permissionDenied) return _permissionDeniedView();
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
        // Low-light warning (S3). Sits above the guidance message.
        if (_lowLight)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCCB26A00), // amber, semi-opaque
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wb_incandescent_outlined,
                      color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Low light — move somewhere brighter for an even result',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

  /// Shown when the camera permission is denied at the point of use. Explains
  /// why the camera is needed and offers a retry plus the import fallback.
  Widget _permissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Camera access is off',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'The camera is used to take your passport or ID photo. '
              'Photos are processed on this device and never uploaded.\n\n'
              'Allow camera access to continue, or import an existing photo '
              'instead.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _permissionDenied = false);
                      _initCamera();
                    },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Allow camera'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Import a photo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small circular icon button used for secondary capture controls (flip).
class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Tooltip(message: tooltip ?? '', child: Icon(icon)),
      ),
    );
  }
}
