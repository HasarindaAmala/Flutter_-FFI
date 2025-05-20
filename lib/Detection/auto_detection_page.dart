import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class AutoDetectionPage extends StatefulWidget {
  final CameraDescription camera;

  const AutoDetectionPage({super.key, required this.camera});

  @override
  State<AutoDetectionPage> createState() => _AutoDetectionPageState();
}

class _AutoDetectionPageState extends State<AutoDetectionPage> {
  late CameraController _controller;
  bool _isDetecting = false;
  Offset? _ledPosition;
  final double _circleRadius = 30.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller.initialize();
    if (!mounted) return;

    _controller.startImageStream((CameraImage image) {
      if (!_isDetecting) {
        _isDetecting = true;
        _detectLED(image).then((position) {
          if (position != null) {
            setState(() => _ledPosition = position);
          }
          _isDetecting = false;
        });
      }
    });

    setState(() {});
  }

  Future<Offset?> _detectLED(CameraImage image) async {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    int maxBrightness = 0;
    Offset? ledPos;

    const int step = 4; // Sample every 4th pixel to reduce processing

    for (int y = 0; y < height; y += step) {
      for (int x = 0; x < width; x += step) {
        final yIndex = y * width + x;
        final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uPlane.bytesPerPixel!;

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        final yf = yVal.toDouble();
        final uf = (uVal - 128).toDouble();
        final vf = (vVal - 128).toDouble();

        int r = (yf + 1.402 * vf).toInt().clamp(0, 255);
        int g = (yf - 0.344136 * uf - 0.714136 * vf).toInt().clamp(0, 255);
        int b = (yf + 1.772 * uf).toInt().clamp(0, 255);

        final brightness = (r + g + b) ~/ 3;

        // Adjust the thresholds based on your LED color
        if (r > 100 && g < 100 && b < 100 && brightness > maxBrightness) {
          maxBrightness = brightness;
          ledPos = Offset(x.toDouble(), y.toDouble());
        }
      }
    }

    if (ledPos != null) {
      // Scale to preview size
      final previewSize = _controller.value.previewSize!;
      double scaleX = MediaQuery.of(context).size.width / previewSize.height;
      double scaleY = MediaQuery.of(context).size.height / previewSize.width;

      return Offset(ledPos.dy * scaleX, ledPos.dx * scaleY); // rotated 90°
    }

    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Auto LED Detection")),
      body: Stack(
        children: [
          CameraPreview(_controller),
          if (_ledPosition != null)
            Positioned(
              left: _ledPosition!.dx - _circleRadius,
              top: _ledPosition!.dy - _circleRadius,
              child: Container(
                width: _circleRadius * 2,
                height: _circleRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent, width: 4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
