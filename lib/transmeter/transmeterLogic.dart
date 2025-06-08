import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/connectionController.dart';

class transmeterLogic extends GetxController{
  late AnimationController controller;
  late Animation<Color?> animation;
  StreamSubscription? connectionStateSubscription;
  final connectionControll = Get.put(connectionController());




  Future<void> showDoneDialog(double width, double height, context) async {
    connectionControll.RX_found == false ? connectionControll.startScan() : ();
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const Text('Connect with LIFI',style: TextStyle(fontSize: 20.0),),
              IconButton(
                  onPressed: () {
                    connectionControll.startScan();
                  },
                  icon: Icon(Icons.restart_alt))
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Container(
                    width: width * 0.2,
                    height: height * 0.2,
                    // color: Colors.red,
                    child: Image(
                      image: AssetImage("Asserts/logo.png"),
                      width: width * 0.07,
                      height: width * 0.07,
                    )),
                SizedBox(
                  height: height * 0.05,
                ),
                Container(
                  width: width * 0.2,
                  height: height * 0.2,
                  color: Colors.transparent,
                  child: GetBuilder<connectionController>(
                    builder: (Controller) {
                      if (Controller.isBluetoothOn == false) {
                        return const Text(
                          "Turn on bluetooth..",
                          style: TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 18), // Added style for visibility
                        );
                      } else if (Controller.foundDevices.isNotEmpty) {
                        return StreamBuilder<String>(
                          initialData: "disconnected",
                          stream: connectionControll.connection.stream,
                          builder: (context, snapshot) {
                            // If snapshot.data changes to "connected", close dialog
                            if (snapshot.data == "connected") {
                              print("connected from dialog");
                              Navigator.pop(context);
                            }
                            // else if(snapshot.data == "disconnected"){
                            //   print("disconnected from dialog");
                            //   Navigator.pop(context);
                            // }

                            return ListView.builder(
                              itemCount: Controller.foundDevices.length,
                              itemBuilder: (context, index) {
                                final device = Controller.foundDevices[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(device.name.isNotEmpty
                                        ? device.name
                                        : "Unknown"),
                                    subtitle: Text(device.id),
                                    trailing: Controller.ConnectedId ==
                                        device.id
                                        ? const Icon(Icons.bluetooth_connected,
                                        color: Colors.greenAccent)
                                        : const Icon(Icons.bluetooth_disabled,
                                        color: Colors.black),
                                    onTap: () async {
                                      if (Controller.RX_found == true) {
                                        await connectionControll.disconnect();
                                        controller.forward();
                                        Navigator.pop(context);
                                      } else {
                                        // Initiate async connect:
                                        connectionControll.connectToDevice(
                                            device.id, device);
                                      }
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        );
                      } else {
                        print("else");
                        return const SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                            child: SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),

                // Text('Would you like to approve of this message?'),
              ],
            ),
          ),
          actions: <Widget>[
             TextButton(
              child: const Text('cancel'),
              onPressed: () {
                controller.forward();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}