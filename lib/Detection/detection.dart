import 'package:c_plugin/c_plugin.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:lifi_reciever/Detection/graphDraw.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  _DetectionScreenState createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  CameraController? _controller;
  Offset? _boxOrigin;
  bool _dragging = false;
  bool _resizing = false;
  Offset? _lastLocalPos;
  bool ledOn = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  double boxWidth = 100.0;
  double boxHeight = 100.0;

  double minVal = 0.0;
  double maxVal = 0.0;

  bool _detecting = false;
  double _avgBrightness = 0;
  String _ledColorName = "Unknown";

  Size? _previewSize; // logical px of preview area

  static const int _kMaxHistory = 100;
  final List<double> _ledHistory = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    _controller = CameraController(
      cams.first,
      ResolutionPreset.ultraHigh,                 // ◀️ much lower than ultraHigh
      enableAudio: false,
      fps: 60,

    );
    await _controller!.initialize();
    _minZoom = await _controller!.getMinZoomLevel();
    _maxZoom = await _controller!.getMaxZoomLevel();
    _currentZoom = _minZoom;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setZoom(double zoom) async {
    // clamp so you don’t exceed the hardware limits
    final z = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(z);
    setState(() => _currentZoom = z);
  }

  @override
  void dispose() {
    if (_detecting) _controller?.stopImageStream();
    _controller?.dispose();
    super.dispose();
  }

  void _toggleDetect() {
    if (_detecting) {
      _controller!.stopImageStream();
      setState(() => _detecting = false);
    } else {
      _controller!.startImageStream(_onFrame);
      setState(() => _detecting = true);
    }
  }

  // void _processFrame(CameraImage img) {
  //   if (_boxOrigin == null || _previewSize == null) return;
  //
  //   // map UI coords → image pixel coords
  //   final pxW = img.width, pxH = img.height;
  //   final sx = pxW / _previewSize!.width;
  //   final sy = pxH / _previewSize!.height;
  //
  //   final x0 = (_boxOrigin!.dx * sx).clamp(0, pxW - 1).toInt();
  //   final y0 = (_boxOrigin!.dy * sy).clamp(0, pxH - 1).toInt();
  //   final w  = (boxWidth  * sx).clamp(1, pxW - x0).toInt();
  //   final h  = (boxHeight * sy).clamp(1, pxH - y0).toInt();
  //
  //   // sum Y-plane
  //   final bytesPerRow = img.planes[0].bytesPerRow;
  //   final yPlane = img.planes[0].bytes;
  //   int sum = 0;
  //   for (int row = 0; row < h; row++) {
  //     final offset = (y0 + row) * bytesPerRow + x0;
  //     sum += yPlane.buffer.asUint8List()[offset : offset + w]
  //       .fold(0, (a, b) => a + b);
  //   }
  //   final avg = sum / (w * h);
  //
  //   if (mounted) {
  //   setState(() => _avgBrightness = avg);
  //   }
  // }

  // Color hueToColor(double hue) {
  //   final h = hue / 60.0;
  //   final c = 1.0;
  //   final x = c * (1 - (h % 2 - 1).abs());
  //
  //   double r = 0, g = 0, b = 0;
  //   if (h >= 0 && h < 1)      { r = c; g = x; b = 0; }
  //   else if (h >= 1 && h < 2) { r = x; g = c; b = 0; }
  //   else if (h >= 2 && h < 3) { r = 0; g = c; b = x; }
  //   else if (h >= 3 && h < 4) { r = 0; g = x; b = c; }
  //   else if (h >= 4 && h < 5) { r = x; g = 0; b = c; }
  //   else if (h >= 5 && h < 6) { r = c; g = 0; b = x; }
  //
  //   return Color.fromARGB(255, (r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt());
  // }

  void _onFrame(CameraImage img) {
    if (_boxOrigin == null || _previewSize == null) return;
    final pxW = img.width, pxH = img.height;
    final sx = pxW / _previewSize!.width;
    final sy = pxH / _previewSize!.height;

    final x0 = (_boxOrigin!.dx * sx).clamp(0, pxW - 1).toDouble();
    final y0 = (_boxOrigin!.dy * sy).clamp(0, pxH - 1).toDouble();
    final w = (boxWidth * sx).clamp(1, pxW - x0).toDouble();
    final h = (boxHeight * sy).clamp(1, pxH - y0).toDouble();

    Rect roi = Offset(x0, y0) & Size(w, h);

    final stats = processFrameColor(
      yPlane:        img.planes[0].bytes,
      uPlane:        img.planes[1].bytes,
      vPlane:        img.planes[2].bytes,
      width:         img.width,
      height:        img.height,
      yRowStride:    img.planes[0].bytesPerRow,
      uvRowStride:   img.planes[1].bytesPerRow,
      uvPixelStride: img.planes[1].bytesPerPixel!,
      roi:           roi,
    );

    final brightness = stats[0];
    final hue        = stats[3];
    final sat        = stats[4];
    final ledHue     = stats[6];
    final colorCode  = stats[6].toInt(); // Extract color code
    final colorName  = ledColorCodeToName(colorCode);

    if (mounted) {
      setState(() {
        _avgBrightness = brightness;
        maxVal = stats[2];
        minVal = stats[1];
        ledOn = stats[5] == 1.0 ? false: true;
        _ledColorName = colorName;
        // record into history
        if (_ledHistory.length >= _kMaxHistory) {
          _ledHistory.removeAt(0);
        }
        _ledHistory.add(ledOn ? 1.0 : 0.0);

      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Preview + ROI
            Expanded(
              flex: 5,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  _previewSize ??= Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
        
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final left = d.localPosition.dx.clamp(
                        0.0,
                        constraints.maxWidth - boxWidth,
                      );
                      final top = d.localPosition.dy.clamp(
                        0.0,
                        constraints.maxHeight - boxHeight,
                      );
                      setState(() => _boxOrigin = Offset(left, top));
                    },
                    onPanStart: (d) {
                      if (_boxOrigin == null) return;
                      final p = d.localPosition;
                      final rect = Rect.fromLTWH(
                        _boxOrigin!.dx,
                        _boxOrigin!.dy,
                        boxWidth,
                        boxHeight,
                      );
                      if (!rect.contains(p)) return;
                      const edge = 20.0;
                      _resizing =
                          (p.dx - rect.right).abs() < edge &&
                          (p.dy - rect.bottom).abs() < edge;
                      _dragging = !_resizing;
                      _lastLocalPos = p;
                    },
                    onPanUpdate: (d) {
                      if (_boxOrigin == null || _lastLocalPos == null) return;
                      final delta = d.localPosition - _lastLocalPos!;
                      _lastLocalPos = d.localPosition;
        
                      setState(() {
                        if (_dragging) {
                          final nx = (_boxOrigin!.dx + delta.dx).clamp(
                            0.0,
                            constraints.maxWidth - boxWidth,
                          );
                          final ny = (_boxOrigin!.dy + delta.dy).clamp(
                            0.0,
                            constraints.maxHeight - boxHeight,
                          );
                          _boxOrigin = Offset(nx, ny);
                        } else if (_resizing) {
                          boxWidth = (boxWidth + delta.dx).clamp(
                            20.0,
                            constraints.maxWidth - _boxOrigin!.dx,
                          );
                          boxHeight = (boxHeight + delta.dy).clamp(
                            20.0,
                            constraints.maxHeight - _boxOrigin!.dy,
                          );
                        }
                      });
                    },
                    onPanEnd: (_) {
                      _dragging = _resizing = false;
                      _lastLocalPos = null;
                    },
                    child: Stack(
                      children: [
                        Center(
                          child: CameraPreview(_controller!),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.zoom_out),
                              onPressed: () => _setZoom(_currentZoom - 0.2),
                            ),
                            Text('${_currentZoom.toStringAsFixed(1)}×'),
                            IconButton(
                              icon: Icon(Icons.zoom_in),
                              onPressed: () => _setZoom(_currentZoom + 0.2),
                            ),
                          ],
                        ),
                        if (_boxOrigin != null)
                          Positioned(
                            left: _boxOrigin!.dx,
                            top: _boxOrigin!.dy,
                            width: boxWidth,
                            height: boxHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 2),
                                color: Colors.red.withOpacity(0.1),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 30.0,
            ),
        
            // Controls
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Width: ${boxWidth.toStringAsFixed(0)}"),
                      Slider(
                        min: 20,
                        max: 500,
                        value: boxWidth,
                        onChanged:
                            (v) => setState(() {
                              boxWidth = v.clamp(
                                20.0,
                                (_previewSize?.width ?? v) - (_boxOrigin?.dx ?? 0),
                              );
                            }),
                      ),
                      Text("Height: ${boxHeight.toStringAsFixed(0)}"),
                      Slider(
                        min: 20,
                        max: 500,
                        value: boxHeight,
                        onChanged:
                            (v) => setState(() {
                              boxHeight = v.clamp(
                                20.0,
                                (_previewSize?.height ?? v) - (_boxOrigin?.dy ?? 0),
                              );
                            }),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _toggleDetect,
                        child: Text(_detecting ? "Stop" : "Detect"),
                      ),
                      if (_detecting) ...[
                        const SizedBox(height: 8),
                        // Column(
                        //   children: [
                        //
                        //     Text(
                        //       "Avg brightness: ${_avgBrightness.toStringAsFixed(1)} ",
                        //       style: const TextStyle(fontSize: 16),
                        //     ),
                        //     Text(
                        //       "Min Max: ${minVal.toStringAsFixed(1)} / ${maxVal.toStringAsFixed(1)}",
                        //       style: const TextStyle(fontSize: 16),
                        //     ),
                        //     Row(
                        //       mainAxisAlignment: MainAxisAlignment.center,
                        //       children: [
                        //         Text(
                        //           "Led on/off : ",
                        //           style: const TextStyle(fontSize: 16),
                        //         ),
                        //         Text(
                        //           ledOn == false? "OFF": "ON",
                        //           style: const TextStyle(fontSize: 16),
                        //         ),
                        //       ],
                        //     ),
                        //     SizedBox(
                        //       height: 15.0,
                        //     ),
                        //     SizedBox(
                        //       height: 120,
                        //       child: CustomPaint(
                        //         painter: LedLinePainter(_ledHistory),
                        //         child: Container(),
                        //       ),
                        //     ),
                        //   ],
                        // ),
                        Column(
                          children: [
                            Text(
                              "Avg brightness: ${_avgBrightness.toStringAsFixed(1)} ",
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              "Min Max: ${minVal.toStringAsFixed(1)} / ${maxVal.toStringAsFixed(1)}",
                              style: const TextStyle(fontSize: 16),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Led on/off : ",
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  ledOn ? "ON" : "OFF",
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            Text(
                              "LED color: $_ledColorName",
                              style: const TextStyle(fontSize: 16),
                            ),

                            const SizedBox(height: 15.0),
                            SizedBox(
                              height: 120,
                              child: CustomPaint(
                                painter: LedLinePainter(_ledHistory),
                                child: Container(),
                              ),
                            ),
                          ],
                        )
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String ledColorCodeToName(int code) {
  switch (code) {
    case 1: return "Red";
    case 2: return "Green";
    case 3: return "Blue";
    case 4: return "Yellow";
    case 5: return "Cyan";
    case 6: return "Magenta";
    default: return "Unknown";
  }
}


