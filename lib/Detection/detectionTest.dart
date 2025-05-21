// lib/main.dart

import 'dart:typed_data';
import 'dart:ui';
import 'package:c_plugin/c_plugin.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';




class DetectionPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DetectionPage({required this.cameras});
  @override
  _DetectionPageState createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  CameraController? _ctl;
  Uint8List?      _lastNv21;    // ← new
  List<Rect> _candidates = [];
  Rect? _roi;
  String _status = 'Detecting bright spots...';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final back = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );
    _ctl = CameraController(
      back,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _ctl!.initialize();
    await _ctl!.startImageStream(_onFrame);
    setState(() {});
  }

  void _onFrame(CameraImage img) async {
    if (_busy || _roi != null) return;
    _busy = true;

    // flatten NV21 byte buffer
    final wb = WriteBuffer();
    for (final p in img.planes) wb.putUint8List(p.bytes);
    final nv21 = wb.done().buffer.asUint8List();
    _lastNv21 = nv21;  // ← store

    // call into your plugin
    final regs = findBrightRegions(
      nv21,
      img.width,
      img.height,
      /*threshold=*/200,
      /*maxRegions=*/5,
    );

    setState(() {
      _candidates = regs;
      _status = 'Tap a box to select ROI';
    });

    _busy = false;
  }

  void _onTapDown(TapDownDetails d, Size previewSize) {
    if (_candidates.isEmpty || _ctl == null) return;

    // The actual frame dimensions (in pixels) coming from the camera:
    final frameSize = _ctl!.value.previewSize!;

    // How much the raw frame is scaled to fit our preview widget:
    final scaleX = previewSize.width  / frameSize.width;
    final scaleY = previewSize.height / frameSize.height;

    final local = d.localPosition;

    for (final r in _candidates) {
      // Scale the candidate rect up to widget coordinates:
      final rect = Rect.fromLTWH(
        r.left   * scaleX,
        r.top    * scaleY,
        r.width  * scaleX,
        r.height * scaleY,
      );

      if (rect.contains(local)) {
        setState(() {
          _roi    = r;
          _status = 'ROI selected – checking LED...';
        });
        _pollLed();
        break;
      }
    }
  }

  Future<void> _pollLed() async {
    while (_roi != null) {
      // take a fresh frame for on/off check
      final img = await _ctl!.takePicture();
      final bytes = await img.readAsBytes();
      // If your native expects NV21 you’d have to re-stream;
      // here we assume you have NV21 from the last stream
      final on = checkLedOn(
        /*nv21=*/_lastNv21!,
        _ctl!.value.previewSize!.width.toInt(),
        _ctl!.value.previewSize!.height.toInt(),
        /*threshold=*/200,
        _roi!,
      );
      setState(() => _status = 'LED is ${on ? 'ON' : 'OFF'}');
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ctl == null || !_ctl!.value.isInitialized) {
      return Scaffold(body: Center(child: Text('Initializing camera...')));
    }
    final previewSize = Size(
      MediaQuery.of(context).size.width,
      MediaQuery.of(context).size.width *
          _ctl!.value.previewSize!.height /
          _ctl!.value.previewSize!.width,
    );

    return Scaffold(
      body: GestureDetector(
        onTapDown: (d) => _onTapDown(d, previewSize),
        child: Stack(children: [
          SizedBox(
            width: previewSize.width,
            height: previewSize.height,
            child: CameraPreview(_ctl!),
          ),
          // draw candidate boxes
          CustomPaint(
            size: previewSize,
            painter: _BoxPainter(
              candidates: _candidates,
              selected: _roi,
              frameSize: _ctl!.value.previewSize!,
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: Text(
              _status,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                backgroundColor: Colors.black54,
              ),
            ),
          )
        ]),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<Rect> candidates;
  final Rect? selected;
  final Size frameSize;
  _BoxPainter({
    required this.candidates,
    this.selected,
    required this.frameSize,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 2..style = PaintingStyle.stroke;
    for (final r in candidates) {
      paint.color = (r == selected) ? Colors.green : Colors.red;
      final scaled = Rect.fromLTWH(
        r.left / frameSize.width * size.width,
        r.top / frameSize.height * size.height,
        r.width / frameSize.width * size.width,
        r.height / frameSize.height * size.height,
      );
      canvas.drawRect(scaled, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => true;
}
