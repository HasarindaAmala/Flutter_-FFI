import 'package:flutter/material.dart';
import 'package:lifi_reciever/splashScreen/splashScreen.dart';

import 'Detection/detection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter FFI',
      home: splashScreen(),
    );
  }
}

