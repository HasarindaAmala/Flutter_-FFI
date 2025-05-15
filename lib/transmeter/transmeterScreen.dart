import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifi_reciever/transmeter/transmeterLogic.dart';
import 'package:get/get.dart';

import '../controllers/connectionController.dart';

class transmeterScreen extends StatefulWidget {
  const transmeterScreen({super.key});

  @override
  State<transmeterScreen> createState() => _transmeterScreenState();
}

class _transmeterScreenState extends State<transmeterScreen> with SingleTickerProviderStateMixin{
  final transmeter_logic = Get.put(transmeterLogic());
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    transmeter_logic.controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    // Define the color animation (from white to red and back to white)
    transmeter_logic.animation = ColorTween(
      begin: Colors.white,
      end: Color(0xFFFF5061).withOpacity(0.6),
    ).animate(transmeter_logic.controller)
      ..addListener(() {
        setState(() {}); // Update UI whenever animation value changes
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          transmeter_logic.controller.reverse(); // Reverse animation when complete
        } else if (status == AnimationStatus.dismissed) {
          transmeter_logic.controller
              .forward(); // Start animation again when dismissed
        }
      });

    // Start the animation
    transmeter_logic.controller.forward();
    transmeter_logic.connectionControll.isEnableBluetooth();
    transmeter_logic.connectionControll.RxfoundController = StreamController<bool>.broadcast();
  }

  @override
  void dispose() {
    transmeter_logic.controller.dispose();
    //mapViewLogic.mapController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(width: width*0.06,),
            GetBuilder<connectionController>(builder: (controller) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    transmeter_logic.controller.stop();
                    transmeter_logic.showDoneDialog(width, height, context);
                  });
                },
                child: Container(
                  width: width * 0.13,
                  height: width * 0.13,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: controller.RX_found == false
                        ? transmeter_logic.animation.value ?? Colors.white
                        : Colors.greenAccent,
                  ),
                  child: Image.asset(
                    "Asserts/reciever.png",
                    width: width * 0.045,
                  ),
                ),
              );
            }),
            SizedBox(width: width*0.175,),
            SizedBox(
              width: width*0.2,
              height: height*0.07,
              child: Image.asset("Asserts/logo.png")
            )
          ],
        ),
        actions: [
          IconButton(onPressed: (){}, icon: Icon(Icons.menu))
        ],


      ),
      body: Stack(
        children: [
          ElevatedButton(onPressed: (){
            transmeter_logic.connectionControll.sendCommand([0xc1,0xa1]);
          }, child: Text("Send Data"))
        ],
      ),
    );
  }
}
