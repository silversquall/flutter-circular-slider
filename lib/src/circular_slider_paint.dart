import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'base_painter.dart';
import 'slider_painter.dart';
import 'utils.dart';

enum CircularSliderMode { singleHandler, doubleHandler }

enum SlidingState { none, endIsBiggerThanStart, endIsSmallerThanStart }

typedef SelectionChanged<T> = void Function(T a, T b, T c);

const MIN_LAPS = 0;
const MAX_LAPS = 9;
const MAX_SLIDER_VALUE = 99;
const MIN_SLIDER_VALUE = 1;

class CircularSliderPaint extends StatefulWidget {
  final CircularSliderMode mode;
  final int init;
  final int end;
  final int divisions;
  final int primarySectors;
  final int secondarySectors;
  final SelectionChanged<int> onSelectionChange;
  final SelectionChanged<int> onSelectionEnd;
  final Color baseColor;
  final Color selectionColor;
  final Color handlerColor;
  final double handlerOutterRadius;
  final Widget child;
  final bool showRoundedCapInSelection;
  final bool showHandlerOutter;
  final double sliderStrokeWidth;
  final bool shouldCountLaps;
  final int laps;
  final bool online;

  CircularSliderPaint({
    @required this.mode,
    @required this.divisions,
    @required this.init,
    @required this.end,
    this.child,
    @required this.primarySectors,
    @required this.secondarySectors,
    @required this.onSelectionChange,
    @required this.onSelectionEnd,
    @required this.baseColor,
    @required this.selectionColor,
    @required this.handlerColor,
    @required this.handlerOutterRadius,
    @required this.showRoundedCapInSelection,
    @required this.showHandlerOutter,
    @required this.sliderStrokeWidth,
    @required this.shouldCountLaps,
    @required this.laps,
    @required this.online,
  });

  @override
  _CircularSliderState createState() => _CircularSliderState();
}

class _CircularSliderState extends State<CircularSliderPaint> {
  bool _isInitHandlerSelected = false;
  bool _isEndHandlerSelected = false;

  SliderPainter _painter;

  /// start angle in radians where we need to locate the init handler
  double _startAngle;

  /// end angle in radians where we need to locate the end handler
  double _endAngle;

  /// the absolute angle in radians representing the selection
  double _sweepAngle;

  /// in case we have a double slider and we want to move the whole selection by clicking in the slider
  /// this will capture the position in the selection relative to the initial handler
  /// that way we will be able to keep the selection constant when moving
  int _differenceFromInitPoint;

  /// will store the number of full laps (2pi radians) as part of the selection
  int _laps;

  /// will be used to calculate in the next movement if we need to increase or decrease _laps
  SlidingState _slidingState = SlidingState.none;

  bool get isDoubleHandler => widget.mode == CircularSliderMode.doubleHandler;

  bool get isSingleHandler => widget.mode == CircularSliderMode.singleHandler;

  bool get isBothHandlersSelected =>
      _isEndHandlerSelected && _isInitHandlerSelected;

  bool get isNoHandlersSelected =>
      !_isEndHandlerSelected && !_isInitHandlerSelected;

  @override
  void initState() {
    super.initState();
    this._laps = widget.laps;
    initImage();
  }

  ui.Image image_online;
  ui.Image image_offline;
  bool isOnlineImageloaded = false;
  bool isOfflineImageloaded = false;

  Future<Null> initImage() async {
    print('IN initImage');
    final ByteData data_channel_status_icon =
        await rootBundle.load('assets/images/channel_status_icon.png');
    image_online = await loadImage(
        new Uint8List.view(data_channel_status_icon.buffer),
        isOnlineImageloaded);

    final ByteData data_channel_status_icon_offline =
        await rootBundle.load('assets/images/channel_status_icon_offline.png');
    image_offline = await loadImage(
        new Uint8List.view(data_channel_status_icon_offline.buffer),
        isOfflineImageloaded);

    _calculatePaintData();
  }

  Future<ui.Image> loadImage(List<int> img, bool loaded) async {
    final Completer<ui.Image> completer = new Completer();
    ui.decodeImageFromList(img, (ui.Image img) {
      setState(() {
        print('img loaded');
        loaded = true;
      });
      return completer.complete(img);
    });
    return completer.future;
  }

  // we need to update this widget both with gesture detector but
  // also when the parent widget rebuilds itself
  @override
  void didUpdateWidget(CircularSliderPaint oldWidget) {
    super.didUpdateWidget(oldWidget);
    //if (oldWidget.init != widget.init || oldWidget.end != widget.end) {
    _calculatePaintData();
    // }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        CustomPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<CustomPanGestureRecognizer>(
          () => CustomPanGestureRecognizer(
            onPanDown: _onPanDown,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
          ),
          (CustomPanGestureRecognizer instance) {},
        ),
      },
      child:
          // Stack(
          //      children: [
          CustomPaint(
        painter: _painter,
        //foregroundPainter: _painter_online,
        /* child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: widget.child,
        ),
        */
      ),
      // Container(color: Colors.green, width: 20, height: 20,)
      // ]),
    );
  }

  bool end_reached = false;
  void _calculatePaintData() {
    var initPercent = isDoubleHandler
        ? valueToPercentage(widget.init, widget.divisions)
        : 0.0;
    var endPercent = valueToPercentage(widget.end, widget.divisions);
    var sweep = getSweepAngle(initPercent, endPercent);

    var previousStartAngle = _startAngle;
    var previousEndAngle = _endAngle;

    _startAngle = isDoubleHandler ? percentageToRadians(initPercent) : 0.0;
    _endAngle = percentageToRadians(endPercent);
    _sweepAngle = percentageToRadians(sweep.abs());

    // update full laps if need be
    if (widget.shouldCountLaps) {
      var newSlidingState = _calculateSlidingState(_startAngle, _endAngle);
      if (isSingleHandler) {
        var calculated_laps;
        calculated_laps = _calculateLapsForsSingleHandler(
            _endAngle, previousEndAngle, _slidingState, _laps);
        if (calculated_laps == MAX_LAPS + 1) {
          //print('IN _calculatePaintData endPercent = ${endPercent.toString()}  widget.end = ${widget.end.toString()} widget.divisions = ${widget.divisions.toString()} previousStartAngle = ${previousStartAngle.toString()}  _startAngle = ${_startAngle.toString()}  _endAngle = ${_endAngle.toString()}  sweep = ${sweep.toString()}  _sweepAngle = ${_sweepAngle.toString()} endReached = ${end_reached.toString()} / laps = ${calculated_laps.toString()}');
        } else {
          _laps = calculated_laps;
        }
        _slidingState = newSlidingState;
      } else {
        // is double handler
        if (newSlidingState != _slidingState) {
          _laps = _calculateLapsForDoubleHandler(
              _startAngle,
              _endAngle,
              previousStartAngle,
              previousEndAngle,
              _slidingState,
              newSlidingState,
              _laps);
          _slidingState = newSlidingState;
        }
      }
    }

    _painter = SliderPainter(
        mode: widget.mode,
        startAngle: _startAngle,
        endAngle: _endAngle,
        sweepAngle: _sweepAngle,
        selectionColor: widget.selectionColor,
        handlerColor: widget.handlerColor,
        handlerOutterRadius: widget.handlerOutterRadius,
        showRoundedCapInSelection: widget.showRoundedCapInSelection,
        showHandlerOutter: widget.showHandlerOutter,
        sliderStrokeWidth: widget.sliderStrokeWidth,
        image: widget.online ? image_online : image_offline);
  }

  int _calculateLapsForsSingleHandler(
      double end, double prevEnd, SlidingState slidingState, int laps) {
    if (slidingState != SlidingState.none) {
      if (radiansWasModuloed(end, prevEnd)) {
        var lapIncrement = end < prevEnd ? 1 : -1;
        var newLaps = laps + lapIncrement;
        return newLaps < 0 ? 0 : newLaps;
      }
    }
    return laps;
  }

  int _calculateLapsForDoubleHandler(
      double start,
      double end,
      double prevStart,
      double prevEnd,
      SlidingState slidingState,
      SlidingState newSlidingState,
      int laps) {
    if (slidingState != SlidingState.none) {
      if (!radiansWasModuloed(start, prevStart) &&
          !radiansWasModuloed(end, prevEnd)) {
        var lapIncrement =
            newSlidingState == SlidingState.endIsBiggerThanStart ? 1 : -1;
        var newLaps = laps + lapIncrement;
        return newLaps < 0 ? 0 : newLaps;
      }
    }
    return laps;
  }

  SlidingState _calculateSlidingState(double start, double end) {
    return end > start
        ? SlidingState.endIsBiggerThanStart
        : SlidingState.endIsSmallerThanStart;
  }

  void _onPanUpdate(Offset details) {
    if (!_isInitHandlerSelected && !_isEndHandlerSelected) {
      return;
    }
    if (_painter.center == null) {
      return;
    }
    _handlePan(details, false);
  }

  void _onPanEnd(Offset details) {
    _handlePan(details, true);

    _isInitHandlerSelected = false;
    _isEndHandlerSelected = false;
  }

  void _handlePan(Offset details, bool isPanEnd) {
    RenderBox renderBox = context.findRenderObject();
    var position = renderBox.globalToLocal(details);

    var angle = coordinatesToRadians(_painter.center, position);
    var percentage = radiansToPercentage(angle);
    var newValue = percentageToValue(percentage, widget.divisions);

    if (isBothHandlersSelected) {
      var newValueInit =
          (newValue - _differenceFromInitPoint) % widget.divisions;
      if (newValueInit != widget.init) {
        var newValueEnd =
            (widget.end + (newValueInit - widget.init)) % widget.divisions;
        widget.onSelectionChange(newValueInit, newValueEnd, _laps);
        if (isPanEnd) {
          widget.onSelectionEnd(newValueInit, newValueEnd, _laps);
        }
      }
      return;
    }

    // isDoubleHandler but one handler was selected
    if (_isInitHandlerSelected) {
      widget.onSelectionChange(newValue, widget.end, _laps);
      if (isPanEnd) {
        widget.onSelectionEnd(newValue, widget.end, _laps);
      }
    } else {
      if (_laps == MAX_LAPS &&
          (newValue == MAX_SLIDER_VALUE || newValue == MAX_SLIDER_VALUE + 1)) {
        end_reached = true;
        newValue = MAX_SLIDER_VALUE;
        _laps = MAX_LAPS;
      } else if (_laps == MIN_LAPS && newValue == 0 ||
          _laps == MIN_LAPS && newValue == 100) {
        end_reached = true;
        newValue = MIN_SLIDER_VALUE;
      }

      if (_laps == MAX_LAPS && newValue == MAX_SLIDER_VALUE - 1) {
        end_reached = false;
      } else if (_laps == MIN_LAPS && (newValue == MIN_SLIDER_VALUE + 1)) {
        end_reached = false;
      }

      /*print('calling widget.onSelectionChange end_reached = ${end_reached
          .toString()} with newValue = ${newValue
          .toString()} with _laps = ${_laps
          .toString()}');
      */
      ////////////////////////////////////////////////////////////////////////
      ///////// custom Code : refreshing _endAngle after the screen is touched
      ////////////////////////////////////////////////////////////////////////

      var initPercent = isDoubleHandler
          ? valueToPercentage(widget.init, widget.divisions)
          : 0.0;
      var endPercent = valueToPercentage(widget.end, widget.divisions);
      var sweep = getSweepAngle(initPercent, endPercent);
      var previousStartAngle = _startAngle;
      var previousEndAngle = _endAngle;

      _startAngle = isDoubleHandler ? percentageToRadians(initPercent) : 0.0;
      _endAngle = percentageToRadians(endPercent);
      _sweepAngle = percentageToRadians(sweep.abs());

      if (!end_reached) {
        widget.onSelectionChange(widget.init, newValue, _laps);
      }

      if (isPanEnd) {
        widget.onSelectionEnd(widget.init, newValue, _laps);
      }
    }
  }

  bool _onPanDown(Offset details) {
    if (_painter == null) {
      return false;
    }
    RenderBox renderBox = context.findRenderObject();
    var position = renderBox.globalToLocal(details);

    var angle = coordinatesToRadians(_painter.center, position);
    var percentage = radiansToPercentage(angle);
    var newValue = percentageToValue(percentage, widget.divisions);

    if (position == null) {
      return false;
    }

    if (isSingleHandler) {
      if (isPointAlongCircle(position, _painter.center, _painter.radius)) {
        _isEndHandlerSelected = true;
        _onPanUpdate(details);
      }
    } else {
      _isInitHandlerSelected = isPointInsideCircle(
          position, _painter.initHandler, widget.handlerOutterRadius);

      if (!_isInitHandlerSelected) {
        _isEndHandlerSelected = isPointInsideCircle(
            position, _painter.endHandler, widget.handlerOutterRadius);
      }

      if (isNoHandlersSelected) {
        // we check if the user pressed in the selection in a double handler slider
        // that means the user wants to move the selection as a whole
        if (isPointAlongCircle(position, _painter.center, _painter.radius)) {
          var angle = coordinatesToRadians(_painter.center, position);
          if (isAngleInsideRadiansSelection(angle, _startAngle, _sweepAngle)) {
            _isEndHandlerSelected = true;
            _isInitHandlerSelected = true;
            var positionPercentage = radiansToPercentage(angle);

            // no need to account for negative values, that will be sorted out in the onPanUpdate
            _differenceFromInitPoint =
                percentageToValue(positionPercentage, widget.divisions) -
                    widget.init;
          }
        }
      }
    }
    return _isInitHandlerSelected || _isEndHandlerSelected;
  }
}

class CustomPanGestureRecognizer extends OneSequenceGestureRecognizer {
  final Function onPanDown;
  final Function onPanUpdate;
  final Function onPanEnd;

  CustomPanGestureRecognizer({
    @required this.onPanDown,
    @required this.onPanUpdate,
    @required this.onPanEnd,
  });

  @override
  void addPointer(PointerEvent event) {
    if (onPanDown(event.position)) {
      startTrackingPointer(event.pointer);
      resolve(GestureDisposition.accepted);
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onPanUpdate(event.position);
    }
    if (event is PointerUpEvent) {
      onPanEnd(event.position);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'customPan';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}
