import 'dart:async';
import 'package:c_plugin/c_plugin.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:lifi_reciever/Detection/graphDraw.dart';
import 'package:flutter/foundation.dart';


List<String> word = [];
List<double> ledtest =[];
List<List<double>> minMax =[];
List<double> brightnessList =[];
int? _lastFrame;
List<int> intervals = [];
int counter = 1;

List<int> ledOnOffCompute = [];
String currentColor = "";
List<List<dynamic>> ledPairCompute = [[], []];
List<List<dynamic>> finalBits = [[], []];
bool bitStart = false;
int? bitStartIndex;

int greenBlinkCount = 0;
bool transmissionStarted = false;
int transmissionStartIndex = -1;
List<int> collectedBits = [];
List<String> collectedColors = [];
String character = "";

/// A small data class to hold one frame’s detection results
class DetectionResult {
  final List<double> stats;     // [Ycurr, Ymin, Ymax, hue, sat, colorVal, ledFlag?]
  final String ledColor;
  final List<double> history;   // up to _kMaxHistory entries
  final bool isLedOn;

  DetectionResult({
    required this.stats,
    required this.ledColor,
    required this.history,
    required this.isLedOn,
  });
}

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  _DetectionScreenState createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  static const warmUpDuration        = Duration(milliseconds: 300);
  static const measurementDuration   = Duration(seconds: 2);
  static const fpsLogInterval        = Duration(milliseconds: 500);

  DateTime?     _warmUpStart;
  DateTime?     _measurementStart;
  bool          _processing = false;
  Timer?        _fpsTimer;
  Timer?        _measurementTimer;
  int           _fpsFrameCount = 0;
  DateTime      _fpsLastTime  = DateTime.now();

  CameraController? _controller;
  bool _cameraInitialized = false;
  // DateTime _fpsLastTime = DateTime.now();
  // int      _fpsFrameCount = 0;

  // ROI state:
  Offset? _boxOrigin;
  double boxWidth = 100.0;
  double boxHeight = 100.0;

  // Zoom state:
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // Detection state:
  bool _detecting = false;
  //bool _processing = false;

  // Latest stats & history
  static const int _kMaxHistory = 100;
  final List<double> _ledHistory = [];
  double _avgBrightness = 0.0;
  double minVal = 0.0, maxVal = 0.0;
  String _ledColorName = "unknown";
  String _currentLedColorName = "unknown";
  double colorCode = 0.0;
  double _ledOn = 0.0;
  final List<int> startingCount = [];
  bool lastWasGreen = false;
  bool lastWasYellow = false;
  bool bitStarted = false;

  bool _samplingBits = false;                // true while reading 8 bits
  int _bitIndex = 0;                         // current bit index (0–7)
  List<int> _bitSamples = [];                // stores the 8-bit result (e.g., [0,1,0,0,1,0,0,0])
  Timer? _samplingTimer;
  final List<String> _ledColorHistory = [];

  // For ROI caching
  Rect? _lastRoi;
  Offset? _lastOrigin;
  double _lastBoxW = 0.0, _lastBoxH = 0.0;

  // Preview size in logical pixels
  Size? _previewSize;
  bool flag = false;

  bool transmittingStart = false;
  // Stream controller for passing results to the UI
  late final StreamController<DetectionResult> _valueController;
  late final StreamController<List<int>> byteController;




  //Timer? _fpsTimer;

  @override
  void initState() {
    super.initState();
    _valueController = StreamController<DetectionResult>.broadcast();
    byteController = StreamController<List<int>>.broadcast();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _controller = CameraController(
        cameras.first,
        ResolutionPreset.low, // Changed from ultraHigh for speed
        enableAudio: false,
        fps: 30,
        imageFormatGroup: ImageFormatGroup.yuv420// Throttle to 30fps—60fps is overkill if we drop frames anyway
    );

    await _controller!.initialize();
    _minZoom = await _controller!.getMinZoomLevel();
    _maxZoom = await _controller!.getMaxZoomLevel();
    _currentZoom = 1.0;
    if (!mounted) return;
    setState(() {
      _cameraInitialized = true;
    });
  }

  Future<void> _setZoom(double zoom) async {
    final z = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(z);
    setState(() => _currentZoom = z);
  }

  @override
  void dispose() {
    if (_detecting) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _valueController.close();
    _fpsTimer?.cancel();
    _measurementTimer?.cancel();
    super.dispose();
  }

  void driveDetection() {
    print("start");
    _warmUpStart        = null;
    _measurementStart   = null;
    _fpsFrameCount      = 0;
    _fpsTimer?.cancel();
    _measurementTimer?.cancel();

    _toggleDetect();

  }

  void _toggleDetect() {
    if (_processing == false && _controller != null && !_detecting) {
      counter = 1;
      minMax.clear();
      ledtest.clear();
      ledOnOffCompute.clear();
      ledPairCompute= [[], []];
      brightnessList.clear();
      finalBits=  [[], []];
      greenBlinkCount = 0;
      bitStart = false;
      character= "Incoming..";
      print("starting output : $finalBits");
      _controller!.startImageStream(_onFrame);

      setState(() => _detecting = true);

    } else if (_controller != null && _detecting) {
      print("final output : $finalBits");
      _controller!.stopImageStream();

      setState(() {
        startingCount.clear();
        _detecting = false;
      });

    }

  }

  // Convert an index to a color name
  static const List<String> _ledColorNames = [
    "black",
    "yellow",
    "gray",
    "red",
    "red",
    "yellow",
    "green",
    "green",
    "blue",
    "magenta",
    "red",
    "unknown",
  ];
  String ledColorDetect(int idx) {
    if (idx < 0 || idx >= _ledColorNames.length) return "unknown";
    return _ledColorNames[idx];
  }



  List<bool> decodeLedHistory(double encoded) {
    int val = encoded.toInt(); // convert from double
    return List<bool>.generate(5, (i) => ((val >> (4 - i)) & 1) == 1);
  }
  void updateLedTest(List<bool> decodedHistory, int frameIndex, List<bool> ledtest) {
    // Order from oldest to newest using circular buffer logic
    for (int i = 0; i < 5; i++) {
      int actualIndex = (frameIndex + 1 + i) % 5;
      // This corresponds to the order: oldest, mid, newest
      bool state = decodedHistory[actualIndex];

      if (ledtest.length <= i + frameIndex) {
        ledtest.add(state); // Not enough data yet
      } else {
        ledtest[ledtest.length - 5 + i] = state;
      }
    }
  }

  void ledMainArrayUpdate (List<bool> history, int frame,){
    void ensureSize(int index) {
      // Extend the mainArray if needed
      while (ledtest.length <= index) {
        ledtest.add(0.0);
      }
    }



    if(frame<6){

      for(int i = 0; i< 5; i++){
        ensureSize(i);
        ledtest[i] = history[i] ? 1.0:0.0;
      }

    }else{
      int a = frame%5;
      int b = (frame-1)%5;
      int c = (frame -2)%5;
      int d = (frame -3)%5;
      int e = (frame -4)%5;

      ensureSize(frame-1);
      ensureSize(frame -2);
      ensureSize(frame -3);
      ensureSize(frame -4);
      ensureSize(frame -5);


      if(a == 0){
        ledtest[frame-1] =  history[4] ? 1.0:0.0 ;
      }else if(a == 1){
        ledtest[frame-1] =  history[0] ? 1.0:0.0 ;
      }else if(a == 2){
        ledtest[frame-1] =  history[1] ? 1.0:0.0 ;
      } else if(a == 3){
        ledtest[frame-1] =  history[2] ? 1.0:0.0 ;
      }else if(a == 4){
        ledtest[frame-1] =  history[3] ? 1.0:0.0 ;
      }

      if(b == 0){
        ledtest[frame-2] =  history[4] ? 1.0:0.0 ;
      }else if(b == 1){
        ledtest[frame-2] =  history[0] ? 1.0:0.0 ;
      }else if(b == 2){
        ledtest[frame-2] =  history[1] ? 1.0:0.0 ;
      } else if(b == 3){
        ledtest[frame-2] =  history[2] ? 1.0:0.0 ;
      }else if(b == 4){
        ledtest[frame-2] =  history[3] ? 1.0:0.0 ;
      }

      if(c == 0){
        ledtest[frame-3] =  history[4] ? 1.0:0.0 ;
      }else if(c == 1){
        ledtest[frame-3] =  history[0] ? 1.0:0.0 ;
      }else if(c == 2){
        ledtest[frame-3] =  history[1] ? 1.0:0.0 ;
      } else if(c == 3){
        ledtest[frame-3] =  history[2] ? 1.0:0.0 ;
      }else if(c == 4){
        ledtest[frame-3] =  history[3] ? 1.0:0.0 ;
      }

      if(d == 0){
        ledtest[frame-4] =  history[4] ? 1.0:0.0 ;
      }else if(d == 1){
        ledtest[frame-4] =  history[0] ? 1.0:0.0 ;
      }else if(d == 2){
        ledtest[frame-4] =  history[1] ? 1.0:0.0 ;
      } else if(d == 3){
        ledtest[frame-4] =  history[2] ? 1.0:0.0 ;
      }else if(d == 4){
        ledtest[frame-4] =  history[3] ? 1.0:0.0 ;
      }

      if(e == 0){
        ledtest[frame-5] =  history[4] ? 1.0:0.0 ;
      }else if(e == 1){
        ledtest[frame-5] =  history[0] ? 1.0:0.0 ;
      }else if(e == 2){
        ledtest[frame-5] =  history[1] ? 1.0:0.0 ;
      } else if(e == 3){
        ledtest[frame-5] =  history[2] ? 1.0:0.0 ;
      }else if(e == 4){
        ledtest[frame-5] =  history[3] ? 1.0:0.0 ;
      }


    }


  }
  void _startFpsTimer() {
    _fpsLastTime = DateTime.now();
    _fpsTimer = Timer.periodic(fpsLogInterval, (timer) {
      final now     = DateTime.now();
      final elapsed = now.difference(_fpsLastTime).inMilliseconds;
      final fps     = elapsed > 0
          ? _fpsFrameCount * 1000 / elapsed
          : 0.0;
      print("FPS: ${fps.toStringAsFixed(1)}");

      // reset counters
      _fpsFrameCount = 0;
      _fpsLastTime   = now;
    });
  }

  void _startMeasurementTimer() {
    _measurementTimer = Timer(measurementDuration, () {
      // stop FPS logging and image stream
      _fpsTimer?.cancel();
      _toggleDetect();
      print("Measurement complete.");
    });
  }

  void _onFrame(CameraImage img) {

    final now = DateTime.now();

    if (_warmUpStart == null) {
      _warmUpStart = now;
      return;  // skip processing/logging until warm-up timer is running
    }
    if (now.difference(_warmUpStart!) < warmUpDuration) {
      return;
    }

    if (_boxOrigin == null || _previewSize == null) return;

    // // ─── 2) Measurement start ──────────────────────────────
    // if (_measurementStart == null) {
    //   _measurementStart = now;
    //   _startFpsTimer();                   // every 500 ms
    //   _startMeasurementTimer();           // single 2 s timer
    // }


    _fpsFrameCount++;
    if(_processing == true){
      print("dropped");
    }
    if (_processing) return;
    _processing = true;

    // Recompute ROI only if ROI changed
    if (_lastOrigin != _boxOrigin ||
        _lastBoxW != boxWidth ||
        _lastBoxH != boxHeight) {
      final sx = img.width / _previewSize!.width;
      final sy = img.height / _previewSize!.height;
      final x0 = (_boxOrigin!.dx * sx).clamp(0.0, img.width - 1).toDouble();
      final y0 = (_boxOrigin!.dy * sy).clamp(0.0, img.height - 1).toDouble();
      final w = (boxWidth * sx).clamp(1.0, img.width - x0).toDouble();
      final h = (boxHeight * sy).clamp(1.0, img.height - y0).toDouble();
      _lastRoi = Offset(x0, y0) & Size(w, h);
      _lastOrigin = _boxOrigin;
      _lastBoxW = boxWidth;
      _lastBoxH = boxHeight;
    }
    final roi = _lastRoi!;

    //print("start function");

    // Call the native FFI function
    final stats = processFrameColor(
      yPlane:        img.planes[0].bytes,
      uPlane:        img.planes[1].bytes,
      vPlane:        img.planes[2].bytes,
      width:         img.width,
      height:        img.height,
      count:         counter-1,
      yRowStride:    img.planes[0].bytesPerRow,
      uvRowStride:   img.planes[1].bytesPerRow,
      uvPixelStride: img.planes[1].bytesPerPixel!,
      roi:           roi,
    );


    // Update all fields, then push to stream
    _avgBrightness = stats[0];
    minVal         = stats[1];
    maxVal         = stats[2];
    colorCode      = stats[5];
    _ledOn         = stats[6];
    //

    minMax.add([minVal,maxVal]);
    List<bool> ledHistory = decodeLedHistory(_ledOn);
    ledMainArrayUpdate(ledHistory,counter);
    //ledtest.add(_ledOn);
    brightnessList.add(_avgBrightness);
    _ledColorName = ledColorDetect(colorCode.toInt());
    collectedColors.add(_ledColorName);
    // if (ledPairCompute.isEmpty) {
    //   ledPairCompute.add([]); // led status row
    //   ledPairCompute.add([]); // color row
    // }
    ledPairCompute[0].add(ledtest[counter-1] == 1.0 ? 1 : 0);
    ledPairCompute[1].add(_ledColorName);

    if(counter == 5){
      for (int i = 0; i <= 4; i++) {
        final onOff = ledtest[i] == 1.0? 1:0;
        ledPairCompute[0][i] = onOff;
        ledPairCompute[1][i] = onOff == 1 ? collectedColors[i] : "Black";
      }
    }

    if (counter > 5 && !bitStart) {
      for (int i = 0; i < ledPairCompute[0].length - 2; i++) {
        if (ledPairCompute[0][i] == 1 && ledPairCompute[0][i + 1] == 1 && ledPairCompute[0][i + 2] == 1) {
          bitStart = true;
          bitStartIndex = i; // Start grouping from here
          break;
        }
      }
    }

// Step 2: Group into 3s and classify (if start was detected)
    if (bitStart && bitStartIndex != null) {
      // Only group chunks that haven’t been grouped before
      int nextGroupStart = bitStartIndex! + finalBits[0].length * 3;

      while (nextGroupStart + 2 < ledPairCompute[0].length){
        int a = ledPairCompute[0][nextGroupStart];
        String colorA = ( a ==1 ?  ledPairCompute[1][nextGroupStart]:"Black"); // ledPairCompute[1][nextGroupStart] = "green"
        int b = ledPairCompute[0][nextGroupStart + 1];
        String colorB =  b == 1?  ledPairCompute[1][nextGroupStart+1]:"Black";
        int c = ledPairCompute[0][nextGroupStart + 2];
        String colorC =  c == 1?  ledPairCompute[1][nextGroupStart+2]:"Black";

        if(colorA == colorB && colorA == colorC && colorA != "Black"){
          //thunama eka pata
          currentColor = colorA;
        }else if((colorA == colorB || colorA == colorC) && colorA != "Black"){
          //color eka A
          currentColor = colorA;
        }else if(colorB ==colorC && colorB != "Black"){
          //color eka B
          currentColor = colorB;
        }else{
          // off state
          currentColor = "Black";
        }
        int sum = a + b + c;
        int decodedBit = sum >= 2 ? 1 : 0; // Majority voting
        decodedBit == 1? finalBits[1].add(currentColor):finalBits[1].add("Black");
        finalBits[0].add(decodedBit);
        nextGroupStart += 3;
      }
    }

    final lp = finalBits;
    final len = lp[0].length;
    if ( !transmissionStarted && len >= 11) {     //!transmissionStarted &&
      if (lp[0][len - 5] == 1 && lp[1][len - 5] == "blue" &&
          lp[0][len - 3] == 1 && lp[1][len - 3] == "blue" &&
          lp[0][len - 1] == 1 && lp[1][len - 1] == "blue"&&
          lp[0][len - 7] == 1 && lp[1][len - 7] == "red" &&
          lp[0][len - 9] == 1 && lp[1][len - 9] == "red" &&
          lp[0][len - 11] == 1 && lp[1][len - 11] == "red"

      ) {
        transmissionStarted = true;
        greenBlinkCount ++;
        transmissionStartIndex = len; // next index is yellow
        print(">>> Transmission started at frame e $transmissionStartIndex");
        // if(transmissionStarted){
        //   _toggleDetect();
        //   transmissionStarted = false;
        //   if(greenBlinkCount == 2){
        //     greenBlinkCount = 0;
        //
        //   }
        //
        // }


      }
    }

    if (transmissionStarted && len >= transmissionStartIndex + 17) {
      List<int> bits = [];
      List<String> colors = [];

      for (int i = transmissionStartIndex+1 ; i <= transmissionStartIndex + 16; i++) {
        final isOn = lp[0][i] == 1;
        final color = lp[1][i];
        final bit = (isOn && color == "red") ? 1 : 0;
        bits.add(bit);
        colors.add(color);
      }
       character = decodeCharacter(bits);
      print(">>> Received 8 bits: $bits");
      print(">>> Colors: $colors");
      print(">>> character : $character");

      // Reset
      transmissionStarted = false;
      if(transmittingStart == false){
        _toggleDetect();
      }
      transmissionStartIndex = -1;

      // Send to UI / controller
      // byteController.sink.add(bits);
    }

    print("count :$counter minVal $minVal maxVal $maxVal brightness $_avgBrightness on/off ${ledtest[counter-1] } dec_no $_ledOn  led_history: $ledHistory  color : $_ledColorName    Hue Val: : ${stats[3]}" );

    // final idx = stats[5].toInt();               // your “colorVal” field
    // final name = ledColorDetect(idx);
    // print("colorVal idx=$idx → $name  (stats[6]=${stats[6]})");
    //
    //
    // if (_ledOn) {
    //   _ledColorName = ledColorDetect(colorCode.toInt());
    //
    //   // Only count a new green when previous was not green
    //   if (_ledColorName == "green" && !lastWasGreen) {
    //     //print("green added");
    //     startingCount.add(1);
    //     transmittingStart = false;
    //     lastWasGreen = true;
    //   }else if(_ledColorName == "yellow" && !lastWasYellow){
    //     flag = false;
    //     print("bit start detected");
    //
    //     bitStarted = true;
    //     lastWasYellow = true;
    //
    //   }else if (_ledColorName != "yellow") {
    //     // As soon as it’s not “yellow” we allow next cycle to retrigger
    //     lastWasYellow = false;
    //   }
    // }
    // else{
    //   print("off");
    //   print("blink detected Black");
    //   if(bitStarted == true){
    //     flag = true;
    //     _ledColorHistory.clear();
    //   }
    //   _ledColorName = "Black";
    //
    //   lastWasGreen = false;
    //   lastWasYellow = false;// Reset when not green
    // }
    // _ledColorHistory.add(_ledColorName);
    // if (_ledHistory.length >= _kMaxHistory) {
    //   _ledHistory.removeAt(0);
    // }
    // if (_ledColorHistory.length >= 80) {
    //   _ledColorHistory.removeAt(0);
    // }
    // _ledHistory.add(_ledOn ? 1.0 : 0.0);
    //
    // if(startingCount.length == 3){
    //   print("start detecting...");
    //   startingCount.clear();
    //   transmittingStart = true;
    // }
    //
    // if(bitStarted ==true && !_samplingBits && flag == true){
    //
    //   print("detection started..");
    //   bitStarted = false;
    //   _samplingBits = true;
    //   _bitSamples.clear();
    //   _bitIndex = 0;
    //   _samplingTimer?.cancel();
    //
    //   // _samplingTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
    //   //   sampleBit();
    //   // });
    //   // Start fixed-interval sampling after a short sync delay (~200ms)
    //
    //
    //   Future.delayed(Duration(milliseconds: 120), () {
    //     print(">>> Color immediately after yellow: $_ledColorName");
    //     sampleBit();
    //     _samplingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
    //       print("sample bit started ...>");
    //       sampleBit();
    //     });
    //   });
    // }
    //
    // // Now trigger a rebuild for anything that depends on this
    // setState(() {});
    // _valueController.add(
    //   DetectionResult(
    //     stats: stats,
    //     ledColor: _ledColorName,
    //     history: List<double>.from(_ledHistory),
    //     isLedOn: _ledOn,
    //   ),
    // );
    counter = counter +1;
    _processing = false;
  }

  String decodeCharacter(List<int> frameBits){
    String char = "";
    if (frameBits.length != 16) return '?';

    List<int> bits = [];

    for (int i = 0; i < 16; i += 2) {
      bits.add(frameBits[i]); // take every ON frame
    }

    int charCode = 0;
    for (int bit in bits) {
      charCode = (charCode << 1) | bit;
    }

    return String.fromCharCode(charCode);
  }

  List<int> encodeRedByNineDropLeading(List<String> input) {
    const int divisions = 9;
    final int n = input.length;
    if (n < divisions) return [];

    // 1) floor(n/9)
    final int chunkSize = n ~/ divisions;

    // 2) drop the first n - 9*chunkSize items
    final int dropLeading = n - chunkSize * divisions;
    final List<String> trimmed = input.sublist(dropLeading);

    // 3) now trimmed.length == 9 * chunkSize
    // 4) build bits for chunks 1..8
    final List<int> bits = [];
    for (int i = 1; i < divisions; i++) {
      final int start = i * chunkSize;
      final int end   = start + chunkSize;
      final chunk     = trimmed.sublist(start, end);

      final redCount = chunk.where((c) => c.toLowerCase() == 'red').length;
      bits.add(redCount > 1 ? 1 : 0);
    }

    return bits;  // always length 8
  }

  void sampleBit() {
    if (_bitIndex >= 8) {
      _samplingTimer?.cancel();
      _samplingBits = false;
      bitStarted = false; // <- ADD THIS
      print("Final color pattern: $_ledColorHistory");
      final result = encodeRedByNineDropLeading(_ledColorHistory);
      print("Final bit pattern: $result");
      byteController.sink.add(result);
      return;
    }
    String currentColor = getCurrentColor(); // Your method to get current LED color
    int bit = (currentColor == "red" || currentColor == "pink") ? 1 : 0;
    _bitSamples.add(bit);
    //print("Bit $_bitIndex: $bit $currentColor");
    _bitIndex++;
  }
  String getCurrentColor() {
    final count = 3;
    final start = (_ledColorHistory.length >= count)
        ? _ledColorHistory.length - count
        : 0;
    final recent = _ledColorHistory.sublist(start);
    // print( "recent: $recent");
    final redCount = recent.where((c) => c == "red").length;

    return (redCount >= 2) ? "red" : "black";
  }


  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    if (!_cameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ───── Preview + ROI ───────────────
            SizedBox(
              width: width,
              height: height*0.6,
              child: LayoutBuilder(builder: (ctx, constraints) {
                // Cache preview size once
                _previewSize ??= Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    // drop the ROI rectangle wherever user taps
                    final left = d.localPosition.dx.clamp(
                      0.0,
                      maxW - boxWidth,
                    );
                    final top = d.localPosition.dy.clamp(
                      0.0,
                      maxH - boxHeight,
                    );
                    setState(() => _boxOrigin = Offset(left, top));
                  },
                  onPanStart: (d) {
                    final origin = _boxOrigin;
                    if (origin == null) return;
                    final p = d.localPosition;
                    final rect = Rect.fromLTWH(
                      origin.dx,
                      origin.dy,
                      boxWidth,
                      boxHeight,
                    );
                    if (!rect.contains(p)) return;
                    const edge = 20.0;
                    _resizing = (p.dx - rect.right).abs() < edge &&
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
                          maxW - boxWidth,
                        );
                        final ny = (_boxOrigin!.dy + delta.dy).clamp(
                          0.0,
                          maxH - boxHeight,
                        );
                        _boxOrigin = Offset(nx, ny);
                      } else if (_resizing) {
                        boxWidth = (boxWidth + delta.dx).clamp(
                          20.0,
                          maxW - _boxOrigin!.dx,
                        );
                        boxHeight = (boxHeight + delta.dy).clamp(
                          20.0,
                          maxH - _boxOrigin!.dy,
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
                      Center(child: CameraPreview(_controller!)),
                      // Zoom controls on top:
                      Positioned(
                        bottom: 16,
                        left: width*0.1,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.zoom_out,color: Colors.white,),
                              onPressed: () => _setZoom(_currentZoom - 0.2),
                            ),
                            Text('${_currentZoom.toStringAsFixed(1)}×',style: TextStyle(color: Colors.white),),
                            IconButton(
                              icon: const Icon(Icons.zoom_in,color: Colors.white,),
                              onPressed: () => _setZoom(_currentZoom + 0.2),
                            ),
                          ],
                        ),
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
              }),
            ),

            Container(
              width: width,
              height: height*0.35,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    StreamBuilder<List<int>>(
                        initialData: [0,1,1,1,1,1,0,0],
                        stream: byteController.stream,
                        builder: (context, snapshot) {
                          return ControlPanel(
                            boxWidth: boxWidth,
                            boxHeight: boxHeight,
                            onWidthChange: (v) {
                              setState(() {
                                boxWidth = v.clamp(
                                  20.0,
                                  (_previewSize?.width ?? v) - (_boxOrigin?.dx ?? 0),
                                );
                              });
                            },
                            onHeightChange: (v) {
                              setState(() {
                                boxHeight = v.clamp(
                                  20.0,
                                  (_previewSize?.height ?? v) - (_boxOrigin?.dy ?? 0),
                                );
                              });
                            },
                            isDetecting: _detecting,
                            arrivedByte: snapshot.data!,
                            transmittingStart: transmittingStart,
                            driveDetection: driveDetection,

                          );
                        }
                    ),

                    // ───── Detection Info (only when detecting) ─────
                    // if (_detecting)
                    //   StreamBuilder<DetectionResult>(
                    //     stream: _valueController.stream,
                    //     builder: (context, snapshot) {
                    //       final data = snapshot.data;
                    //       return DetectionInfo(
                    //         stats: data?.stats,
                    //         ledColor: data?.ledColor,
                    //         history: data?.history,
                    //         isLedOn: data?.isLedOn ?? false,
                    //       );
                    //     },
                    //   ),
                  ],
                ),
              ),
            ),

            // ───── Controls (width, height, toggle detect) ─────

          ],
        ),
      ),
    );
  }

  // Helpers for drag/resizing
  bool _dragging = false;
  bool _resizing = false;
  Offset? _lastLocalPos;
}

/// A small widget that holds the sliders and Detect/Stop button.
/// Only rebuilds when boxWidth/boxHeight or _detecting change.
class ControlPanel extends StatelessWidget {
  final double boxWidth;
  final double boxHeight;
  final bool isDetecting;
  final ValueChanged<double> onWidthChange;
  final ValueChanged<double> onHeightChange;
  final VoidCallback driveDetection;
  final List<int> arrivedByte;
  final bool transmittingStart;

  const ControlPanel({
    super.key,
    required this.boxWidth,
    required this.boxHeight,
    required this.onWidthChange,
    required this.onHeightChange,
    required this.isDetecting,
    required this.driveDetection,
    required this.arrivedByte,
    required this.transmittingStart,
  });

  String ByteToString(List<int> bits) {
    if (bits.length != 8) {
      print("not enough bits");
      return "";
    }else{
      // Build an integer from the 8 bits
      int value = 0;
      for (int i = 0; i < 8; i++) {
        final bit = bits[i];
        if (bit != 0 && bit != 1) {
          throw ArgumentError("Each element must be 0 or 1. Found: $bit at index $i.");
        }
        // shift existing value left by 1, then OR in the next bit
        value = (value << 1) | bit;
      }

      // Convert that 0–255 value into a single-character string
      return String.fromCharCode(value);
    }


  }



  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 5),
            Text("Width: ${boxWidth.toStringAsFixed(0)}"),
            Slider(
              min: 20,
              max: 500,
              value: boxWidth,
              onChanged: onWidthChange,
            ),
            Text("Height: ${boxHeight.toStringAsFixed(0)}"),
            Slider(
              min: 20,
              max: 500,
              value: boxHeight,
              onChanged: onHeightChange,
            ),
            const SizedBox(height: 6),
            ElevatedButton(
              onPressed: driveDetection,
              child: Text(isDetecting ? "Stop" : "Detect"),
            ),
            const SizedBox(height: 8),
            Text("Character : $character "),

            // SizedBox(
            //   height: 150,
            //   child: SingleChildScrollView(
            //     child: Text(
            //       formatOnOffComputeList(ledOnOffCompute),
            //       style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            //     ),
            //   ),
            // ),
            // Text("on/off values: ${ledOnOffCompute.length}"),
          ],
        ),
      ),
    );
  }
}
String formatList(List<double> list, {int wrap = 10}) {
  final buffer = StringBuffer();
  for (int i = 0; i < list.length; i++) {
    buffer.write(list[i]);
    if ((i + 1) % wrap == 0) buffer.write('\n');
    else buffer.write(', ');
  }
  return buffer.toString();
}
String formatBrightnessList(List<double> list, {int wrap = 10}) {
  final buffer = StringBuffer();
  for (int i = 0; i < list.length; i++) {
    buffer.write(list[i]);
    if ((i + 1) % wrap == 0) buffer.write('\n');
    else buffer.write(', ');
  }
  return buffer.toString();
}
String formatminMaxList(List<List<double>> list, {int wrap = 10}) {
  final buffer = StringBuffer();
  for (int i = 0; i < list.length; i++) {
    buffer.write(list[i]);
    if ((i + 1) % wrap == 0) buffer.write('\n');
    else buffer.write(', ');
  }
  return buffer.toString();
}
String formatOnOffComputeList(List<int> list, {int wrap = 10}) {
  final buffer = StringBuffer();
  for (int i = 0; i < list.length; i++) {
    buffer.write(list[i]);
    if ((i + 1) % wrap == 0) buffer.write('\n');
    else buffer.write(', ');
  }
  return buffer.toString();
}

class DetectionInfo extends StatelessWidget {
  final List<double>? stats;   // null until first frame arrives
  final String? ledColor;
  final List<double>? history;
  final bool isLedOn;

  const DetectionInfo({
    super.key,
    this.stats,
    this.ledColor,
    this.history,
    required this.isLedOn,
  });

  @override
  Widget build(BuildContext context) {
    if (stats == null || ledColor == null || history == null) {
      // Still waiting for first result
      return const Center(child: Text("Detecting..."));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Color: $ledColor",
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            "Min/Max: ${stats![1].toStringAsFixed(1)} / ${stats![2].toStringAsFixed(1)}",
            style: const TextStyle(fontSize: 16),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "LED on/off: ",
                style: TextStyle(fontSize: 16),
              ),
              Text(
                isLedOn ? "ON" : "OFF",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: LedLinePainter(history!),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}