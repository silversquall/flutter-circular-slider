import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'circular_slider_paint.dart' show CircularSliderMode;
import 'utils.dart';

class SliderPainter extends CustomPainter {
  CircularSliderMode mode;
  double startAngle;
  double endAngle;
  double sweepAngle;
  Color selectionColor;
  Color handlerColor;
  double handlerOutterRadius;
  bool showRoundedCapInSelection;
  bool showHandlerOutter;
  double sliderStrokeWidth;

  Offset initHandler;
  Offset endHandler;
  Offset center;
  double radius;

  ui.Image image;
  SliderPainter(
      {@required this.mode,
      @required this.startAngle,
      @required this.endAngle,
      @required this.sweepAngle,
      @required this.selectionColor,
      @required this.handlerColor,
      @required this.handlerOutterRadius,
      @required this.showRoundedCapInSelection,
      @required this.showHandlerOutter,
      @required this.sliderStrokeWidth,
      @required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    if (image != null) {
      Paint progress = _getPaint(color: selectionColor);

      center = Offset(
          size.width / 2 - image.width / 2, size.height / 2 - image.height / 2);
      radius = min(size.width / 2, size.height / 2) - sliderStrokeWidth + 5;

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          -pi / 2 + startAngle, sweepAngle, false, progress);

      endHandler = radiansToCoordinates(center, -pi / 2 + endAngle, radius);

      // draw image
      canvas.drawImage(image, endHandler, Paint());
    }
  }

  Paint _getPaint({@required Color color, double width, PaintingStyle style}) =>
      Paint()
        ..color = color
        ..strokeCap =
            showRoundedCapInSelection ? StrokeCap.round : StrokeCap.butt
        ..style = style ?? PaintingStyle.stroke
        ..strokeWidth = width ?? sliderStrokeWidth;

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
