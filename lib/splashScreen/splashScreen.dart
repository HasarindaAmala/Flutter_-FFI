import 'package:flutter/material.dart';
import 'package:gif/gif.dart';

import '../Home/homeScreen.dart';

class splashScreen extends StatefulWidget {
  const splashScreen({super.key});

  @override
  State<splashScreen> createState() => _splashScreenState();
}

class _splashScreenState extends State<splashScreen> with TickerProviderStateMixin {
  late GifController splashController;

  @override
  void initState() {
    // TODO: implement initState
   // Only once
    splashController = GifController(vsync: this);
    super.initState();
  }
  bool _isLoaded = false; // Add this flag

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded) {
      // Precache images when dependencies change (after initState)
      precacheImage(const AssetImage("Asserts/lifiBanner.png"), context);
      precacheImage(const AssetImage("Asserts/buttonTx.png"), context);
      precacheImage(const AssetImage("Asserts/buttonRx.png"), context);
      _isLoaded = true;
    }
  }

  @override
  void dispose() {
    // TODO: implement dispose
    splashController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return WillPopScope(
      onWillPop: ()async{
        Navigator.pop(context, false);
        return false;
      },
      child: Scaffold(
        backgroundColor: Color(0xFFF9F9F9),
        body: Stack(
          children: [
            Gif(
              fit: BoxFit.fitWidth,
              width: width,
              height: height,
              image: const AssetImage("Asserts/splashScreen.gif"),
              controller: splashController,
              fps: 30,
              autostart: Autostart.no,
              onFetchCompleted: () {
                splashController.reset();
                splashController.forward().then((_){
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => (
                        homeScreen()
                    )),
                  );
                });
              },
            ),

          ],
        ),
      ),
    );
  }
}
