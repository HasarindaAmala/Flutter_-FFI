import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:lifi_reciever/transmeter/transmeterScreen.dart';
import '../Detection/detection.dart';
import '../Detection/detectionTest.dart';
import '../Detection/detection_page.dart';
import '../controllers/connectionController.dart';
import '../reciever/recieverScreen.dart';
import 'package:get/get.dart';

class homeScreen extends StatefulWidget {
  const homeScreen({super.key});

  @override
  State<homeScreen> createState() => _homeScreenState();
}

class _homeScreenState extends State<homeScreen> {
  final connectionControll = Get.put(connectionController());

  Future<bool?> _showExitConfirmation() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you want to exit the application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    connectionControll.requestBluetoothPermissions();
  }

  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height;
    double width = MediaQuery.of(context).size.width;
    return WillPopScope(
      onWillPop: () async {
        final shouldExit = await _showExitConfirmation();
        return shouldExit ?? false;
      },
      child: Scaffold(
        backgroundColor: Color(0xFFFBFBFB),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                SizedBox(height: height * 0.2),
                Image(image: AssetImage("Asserts/lifiBanner.png")),
                SizedBox(height: height*0.1,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => (
                              transmeterScreen()
                          )),
                        );
                      },
                      child: Image(
                        width: width*0.35,
                          image: AssetImage("Asserts/buttonTx.png")),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final cameras = await availableCameras();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => (
                              DetectionScreen()
                          )),
                        );
                      },
                      child: Image(
                          width: width*0.35,
                          image: AssetImage("Asserts/buttonRx.png")),
                    ),
                  ],
                ),

              ],
            ),
          ],
        ),
      ),
    );
  }
}
