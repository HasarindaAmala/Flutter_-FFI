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


// import 'dart:developer';
// import 'dart:io';
// import 'dart:ffi';
// import 'dart:typed_data';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:ffi/ffi.dart';
// import 'package:c_plugin/c_plugin.dart';
//
// class DetectionPage extends StatefulWidget {
//   const DetectionPage({Key? key}) : super(key: key);
//
//   @override
//   _DetectionPageState createState() => _DetectionPageState();
// }
//
// class _DetectionPageState extends State<DetectionPage> with WidgetsBindingObserver {
//   CameraController? _camController;
//   int _camFrameRotation = 0;
//   double _camFrameToScreenScale = 0;
//   int _lastRun = 0;
//   bool _detectionInProgress = false;
//
//   Offset? _ledCenter;
//   double _ledRadius = 40;
//   String _ledStatus = "Tap LED to detect";
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     initCamera();
//   }
//
//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     final CameraController? cameraController = _camController;
//     if (cameraController == null || !cameraController.value.isInitialized) return;
//
//     if (state == AppLifecycleState.inactive) {
//       cameraController.dispose();
//     } else if (state == AppLifecycleState.resumed) {
//       initCamera();
//     }
//   }
//
//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _camController?.dispose();
//     super.dispose();
//   }
//
//   Future<void> initCamera() async {
//     final cameras = await availableCameras();
//     var idx = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
//     if (idx < 0) {
//       log("No Back camera found");
//       return;
//     }
//
//     var desc = cameras[idx];
//     _camFrameRotation = Platform.isAndroid ? desc.sensorOrientation : 0;
//     _camController = CameraController(
//       desc,
//       ResolutionPreset.ultraHigh,
//       enableAudio: false,
//       imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
//     );
//
//     try {
//       await _camController!.initialize();
//       await _camController!.startImageStream((image) => _processCameraImage(image));
//     } catch (e) {
//       log("Error initializing camera: ${e.toString()}");
//     }
//
//     if (mounted) {
//       setState(() {});
//     }
//   }
//
//   void _processCameraImage(CameraImage image) async {
//     if (_detectionInProgress ||
//         !mounted ||
//         DateTime.now().millisecondsSinceEpoch - _lastRun < 300 ||
//         _ledCenter == null) return;
//
//     _detectionInProgress = true;
//     _lastRun = DateTime.now().millisecondsSinceEpoch;
//
//     try {
//       final scale = _camFrameToScreenScale == 0
//           ? MediaQuery.of(context).size.width /
//           ((_camFrameRotation == 0 || _camFrameRotation == 180)
//               ? image.width
//               : image.height)
//           : _camFrameToScreenScale;
//
//       final centerX = (_ledCenter!.dx / scale).toInt();
//       final centerY = (_ledCenter!.dy / scale).toInt();
//
//       // Flatten YUV data
//       final bytes = WriteBuffer();
//       for (var plane in image.planes) {
//         bytes.putUint8List(plane.bytes);
//       }
//       final byteData = bytes.done();
//       final pointer = calloc<Uint8>(byteData.lengthInBytes);
//       final byteList = pointer.asTypedList(byteData.lengthInBytes);
//       byteList.setAll(0, byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
//
//       // Call native
//       final result = processFrame(pointer, image.width, image.height, centerX, centerY, _ledRadius.toInt());
//
//       calloc.free(pointer);
//
//       if (result == nullptr) {
//         print("Null result from native processFrame");
//         return;
//       }
//
//       setState(() {
//         _ledStatus = "LED is ${result.ref.isOn == 1 ? "ON" : "OFF"}";
//       });
//
//     } catch (e) {
//       print("FFI error: $e");
//     }
//
//     _detectionInProgress = false;
//   }
//
//
//   @override
//   Widget build(BuildContext context) {
//     if (_camController == null || !_camController!.value.isInitialized) {
//       return const Scaffold(
//         body: Center(child: Text('Loading Camera...')),
//       );
//     }
//
//     return Scaffold(
//       body: GestureDetector(
//         onTapDown: (details) {
//           setState(() {
//             _ledCenter = details.localPosition;
//           });
//         },
//         child: Stack(
//           children: [
//             CameraPreview(_camController!),
//             if (_ledCenter != null)
//               Positioned(
//                 left: _ledCenter!.dx - _ledRadius,
//                 top: _ledCenter!.dy - _ledRadius,
//                 child: Container(
//                   width: _ledRadius * 2,
//                   height: _ledRadius * 2,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     border: Border.all(color: Colors.greenAccent, width: 2),
//                   ),
//                 ),
//               ),
//             Positioned(
//               bottom: 80,
//               left: 20,
//               right: 20,
//               child: Slider(
//                 value: _ledRadius,
//                 min: 10,
//                 max: 100,
//                 label: "ROI Radius",
//                 onChanged: (value) {
//                   setState(() {
//                     _ledRadius = value;
//                   });
//                 },
//               ),
//             ),
//             Positioned(
//               bottom: 20,
//               left: 20,
//               child: Text(
//                 _ledStatus,
//                 style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   backgroundColor: Colors.black54,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
