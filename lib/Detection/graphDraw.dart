import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LedLinePainter extends CustomPainter {
  final List<double> data;
  LedLinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    // 1) Draw Y axis (left) and X axis (bottom)
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), axisPaint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), axisPaint);

    // 2) Draw Y-axis labels "1.0" at top, "0.0" at bottom
    final textStyle = TextStyle(color: Colors.black, fontSize: 10);
    void drawLabel(String txt, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: txt, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }
    drawLabel('1.0', Offset(2, -tpHeight('1.0', textStyle) / 2));
    drawLabel('0.0', Offset(2, size.height - tpHeight('0.0', textStyle)));

    // 3) Draw the data line
    if (data.length < 2) return;
    final step = size.width / (data.length - 1);
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height * (1 - data[i]); // invert so 1.0→top, 0.0→bottom
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  double tpHeight(String txt, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: txt, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.height;
  }

  @override
  bool shouldRepaint(covariant LedLinePainter old) =>
      !listEquals(old.data, data);
}