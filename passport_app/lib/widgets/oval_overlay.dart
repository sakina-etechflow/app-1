import 'package:flutter/material.dart';

/// A dimmed frame with a transparent oval head-guide and a horizon line, drawn
/// over the camera preview to help the user position their head.
///
/// [ready] turns the guide green when all live checks pass (auto-capture is
/// about to fire).
class OvalOverlay extends StatelessWidget {
  const OvalOverlay({super.key, this.ready = false});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _OvalPainter(ready: ready),
      ),
    );
  }
}

class _OvalPainter extends CustomPainter {
  _OvalPainter({required this.ready});

  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final ovalW = size.width * 0.62;
    final ovalH = ovalW * 1.3;
    final rect = Rect.fromCenter(
      // Keep in sync with LiveCoach centering target (0.5 w, 0.44 h).
      center: Offset(size.width / 2, size.height * 0.44),
      width: ovalW,
      height: ovalH,
    );

    // Dim everything outside the oval.
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Oval guide.
    final guideColor = ready
        ? const Color(0xFF4CAF50)
        : Colors.white.withValues(alpha: 0.9);
    canvas.drawOval(
      rect,
      Paint()
        ..color = guideColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ready ? 4 : 2.5,
    );

    // Horizon (eye) line.
    final eyeY = rect.top + rect.height * 0.42;
    canvas.drawLine(
      Offset(rect.left - 10, eyeY),
      Offset(rect.right + 10, eyeY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalPainter oldDelegate) =>
      oldDelegate.ready != ready;
}
