import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  CameraController? _camController;
  Offset? _tapPosition;
  String _ledStatus = '';
  bool _analyzing = false;
  bool _isStoring = false;
  List<int> _bitBuffer = [];
  int? _lastStoredBit;

  static const int circleRadius = 30;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final backCam = cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.back);

    _camController = CameraController(
      backCam,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _camController!.initialize();
    setState(() {});
    _startImageStream();
  }

  void _startImageStream() {
    _camController!.startImageStream((CameraImage image) async {
      if (_tapPosition == null || _analyzing || !_isStoring) return;

      _analyzing = true;
      final result = await _analyzeLED(image);
      setState(() {
        _ledStatus = result;
      });
      _analyzing = false;
    });
  }

  Future<String> _analyzeLED(CameraImage image) async {
    try {
      final width = image.width;
      final height = image.height;

      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final previewSize = _camController!.value.previewSize!;
      final screenW = previewSize.height;
      final screenH = previewSize.width;

      final scaleX = width / screenW;
      final scaleY = height / screenH;

      // Correct axis mapping for portrait mode
      final y = (_tapPosition!.dy * scaleY).toInt();
      final x = (_tapPosition!.dx * scaleX).toInt();

      if (x < 0 || y < 0 || x >= width || y >= height) {
        return 'Invalid tap position';
      }

      bool isOn = false;

      for (int dx = -circleRadius; dx <= circleRadius; dx++) {
        for (int dy = -circleRadius; dy <= circleRadius; dy++) {
          final px = x + dx;
          final py = y + dy;

          if (px < 0 || py < 0 || px >= width || py >= height) continue;
          if (sqrt(dx * dx + dy * dy) > circleRadius) continue;

          final uvIndex = (py ~/ 2) * uPlane.bytesPerRow + (px ~/ 2);
          final yVal = yBytes[py * width + px];
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];

          final yf = yVal.toDouble();
          final uf = (uVal - 128).toDouble();
          final vf = (vVal - 128).toDouble();

          int r = (yf + 1.402 * vf).toInt().clamp(0, 255);
          int g = (yf - 0.344136 * uf - 0.714136 * vf).toInt().clamp(0, 255);
          int b = (yf + 1.772 * uf).toInt().clamp(0, 255);

          if (r > 100 && g < 100 && b < 100) {
            isOn = true;
          }
        }
      }

      if (isOn) {
        if (_lastStoredBit != 1) {
          _bitBuffer.add(1);
          _lastStoredBit = 1;
        }
        return 'LED is ON';
      } else {
        if (_lastStoredBit != 0) {
          _bitBuffer.add(0);
          _lastStoredBit = 0;
        }
        return 'LED is OFF';
      }
    } catch (e) {
      print('Error during analysis: $e');
      return 'Error';
    }
  }

  void _startStoring() {
    if (_tapPosition == null) {
      setState(() => _ledStatus = "Tap a region to start detecting");
      return;
    }
    setState(() {
      _bitBuffer.clear();
      _lastStoredBit = null;
      _isStoring = true;
      _ledStatus = "Started storing...";
    });
    print(">> Storing started");
  }

  void _stopStoring() {
    setState(() {
      _isStoring = false;
      _ledStatus = "Stopped storing. Buffer saved.";
    });
    print(">> Storing stopped. Buffer: $_bitBuffer");
  }

  @override
  void dispose() {
    _camController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _camController == null || !_camController!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (details) {
                final renderBox = context.findRenderObject() as RenderBox;
                final local = details.localPosition;

                final screenHeight = renderBox.size.height;
                final bottomPanelHeight = 180;
                if (local.dy > screenHeight - bottomPanelHeight) return;

                setState(() {
                  _tapPosition = local;
                  _ledStatus = "Target area selected";
                });
              },
              child: CameraPreview(_camController!),
            ),
          ),
          if (_tapPosition != null)
            Positioned(
              left: _tapPosition!.dx - circleRadius,
              top: _tapPosition!.dy - circleRadius,
              child: Container(
                width: circleRadius * 2,
                height: circleRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.greenAccent, width: 4),
                ),
              ),
            ),
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _ledStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, -4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Controls",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _startStoring,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Start Storing"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _stopStoring,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop Storing"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


