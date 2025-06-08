import 'dart:async';
import 'dart:convert';

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
  TextEditingController interval =  TextEditingController();
  TextEditingController intervalMatrix =  TextEditingController();
  late StreamController<bool> isWriting;
  late TextEditingController commandText;
  int blinkingInterval = 0;
  int hi = 0;
  int lo = 0;
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    transmeter_logic.controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    isWriting = StreamController.broadcast();
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
    commandText = TextEditingController();
  }

  @override
  void dispose() {
    transmeter_logic.controller.dispose();
    commandText.dispose();
    //mapViewLogic.mapController.dispose();
    super.dispose();
  }
  String dropdownvalue = 'Red';
  String dropdownvalueMatrix = 'Red';
  String bulbIdx = '1';

  // List of items in our dropdown menu
  var items = [
    'Red',
    'Green',
    'Blue',
    'Yellow',
    'Magenta',
    'Cyan'
  ];
  var index = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31',
    '32'

  ];

  final List<List<int>> colorPresets = [
    [255, 0,   0],   // Red
    [0,   235, 0],   // Green
    [0,   0,   255], // Blue
    [255, 255, 0],   // Yellow
    [255, 0,   255], // Magenta
    [0,   255, 255], // Cyan
  ];

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
      body: SingleChildScrollView(
        child: Stack(
        
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding:EdgeInsets.only(top: height*0.05),
                    child: Container(
                      width: width*0.9,
                      height: height*0.33,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:  EdgeInsets.only(left: 20.05,top: height*0.02),
                            child: Row(
        
                              children: [
                                Text("Share IT",style: TextStyle(color: Colors.white),),
                                SizedBox(width: 10.0,),
                                Icon(Icons.send_time_extension_rounded,color: Colors.white,),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 20,top: 10.0),
                            child: Container(
                              width: width*0.8,
                              height: height*0.18,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                borderRadius: BorderRadius.circular(10.0)
                              ),
                              child: StreamBuilder<bool>(
                                initialData: false,
                                stream: isWriting.stream,
                                builder: (context, snapshot) {
                                  if(snapshot.data == true){
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: TextFormField(
                                          controller: commandText,
                                          decoration: InputDecoration(
                                            hintText: "Type here..",
                                            hintStyle: TextStyle(color: Colors.black),
                                          ),
                                          style: TextStyle(color: Colors.black),
                                        ),
                                      ),
                                    );
                                  }else{
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add,color: Colors.black38,),
                                          Text("Attach or write data to transfer",style: TextStyle(color: Colors.black38),),
                                        ],
                                      ),
                                    );
                                  }

                                }
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10.0,right: 20.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(onPressed: (){
                                  isWriting.sink.add(true);
                                }, icon: Icon(Icons.note_alt_outlined,color: Colors.white,)),
                                Row(
                                  children: [
                                    IconButton(onPressed: (){}, icon: Icon(Icons.attachment,size: 25,color: Colors.white,)),
                                    ElevatedButton(onPressed: (){
                                      final cmd = commandText.text;
                                      final text6 = utf8.encode(cmd);
                                      print(text6);
                                      transmeter_logic.connectionControll.sendCommand(text6);
                                    }, child: Text("send")),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Container(
                      width: width*0.9,
                      height: height*0.13,
        
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0,top: 10.0),
                            child: Text("LED Controller",style: TextStyle(color: Colors.white),),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0,right: 12.0,top: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                DropdownButton(
                                  dropdownColor: Colors.black87,
        
                                  style: TextStyle(color: Colors.white),
                                  // Initial Value
                                  value: dropdownvalue,
                                  // Down Arrow Icon
                                  icon: const Icon(Icons.keyboard_arrow_down,color: Colors.white,),
        
                                  // Array list of items
                                  items:
                                  items.map((String items) {
                                    return DropdownMenuItem(value: items, child: Text(items));
                                  }).toList(),
                                  // After selecting the desired option,it will
                                  // change button value to selected value
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      dropdownvalue = newValue!;
                                    });
                                  },
                                ),
                                SizedBox(
                                  width: width*0.2,
                                  height: 20.0,
                                  child: TextFormField(
                                    style: TextStyle(
                                      color: Colors.white
                                    ),
                                    keyboardType: TextInputType.number,
                                    controller: interval,
                                    decoration: InputDecoration(
                                      hintText: "Interval",
                                      hintStyle: TextStyle(color: Colors.white),
                                    ),
        
                                  ),
                                ),
                                ElevatedButton(onPressed: (){
                                  // 1) Figure out your color index & RGB
                                  final idx = items.indexOf(dropdownvalue);
                                  final rgb = colorPresets[idx];
        
        
        
                                  // 2) Parse interval text exactly once:
                                  final text = interval.text.trim();
                                  final msInput = int.tryParse(text) ?? 0;
        
                                  // 3) Compute hi/lo _before_ building the list:
                                  final hi = (msInput >> 8) & 0xFF;   // high byte
                                  final lo = msInput & 0xFF;          // low  byte
        
                                  // 4) Build a true List<int> of length 6
                                  final cmd = <int>[
                                    2,          // your blink‐mode
                                    rgb[0],     // R
                                    rgb[1],     // G
                                    rgb[2],     // B
                                    hi,         // interval high byte
                                    lo
        
                                    // interval low  byte
                                  ];
        
                                  print("🔵 Sending command: $cmd");  // debug, should show 6 items
                                  transmeter_logic.connectionControll.sendCommand(cmd);
                                },
                                onLongPress: (){
                                  final cmd = <int>[
                                    0,          // your blink‐mode
                                    0,     // R
                                    0,     // G
                                    0,     // B
                                    hi,         // interval high byte
                                    lo          // interval low  byte
                                  ];
                                  transmeter_logic.connectionControll.sendCommand(cmd);
                                },
                                    child: Text("Send"))
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Container(
                      width: width*0.9,
                      height: height*0.2,
        
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0,top: 10.0),
                            child: Text("Matrix Controller",style: TextStyle(color: Colors.white),),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0,top: 10.0),
                            child: DropdownButton(
                              dropdownColor: Colors.black87,
        
                              style: TextStyle(color: Colors.white),
                              // Initial Value
                              value: bulbIdx,
                              // Down Arrow Icon
                              icon: const Icon(Icons.keyboard_arrow_down,color: Colors.white,),
        
                              // Array list of items
                              items:
                              index.map((String index) {
                                return DropdownMenuItem(value: index, child: Text(index));
                              }).toList(),
                              // After selecting the desired option,it will
                              // change button value to selected value
                              onChanged: (String? newValue) {
                                setState(() {
                                  bulbIdx = newValue!;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0,right: 12.0,top: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                DropdownButton(
                                  dropdownColor: Colors.black87,
        
                                  style: TextStyle(color: Colors.white),
                                  // Initial Value
                                  value: dropdownvalueMatrix,
                                  // Down Arrow Icon
                                  icon: const Icon(Icons.keyboard_arrow_down,color: Colors.white,),
        
                                  // Array list of items
                                  items:
                                  items.map((String items) {
                                    return DropdownMenuItem(value: items, child: Text(items));
                                  }).toList(),
                                  // After selecting the desired option,it will
                                  // change button value to selected value
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      dropdownvalueMatrix = newValue!;
                                    });
                                  },
                                ),
                                SizedBox(
                                  width: width*0.2,
                                  height: 20.0,
                                  child: TextFormField(
                                    style: TextStyle(
                                        color: Colors.white
                                    ),
                                    keyboardType: TextInputType.number,
                                    controller: intervalMatrix,
                                    decoration: InputDecoration(
                                      hintText: "Interval",
                                      hintStyle: TextStyle(color: Colors.white),
                                    ),
        
                                  ),
                                ),
                                ElevatedButton(onPressed: (){
                                  // 1) Figure out your color index & RGB
                                  final idx = items.indexOf(dropdownvalueMatrix);
                                  final rgb = colorPresets[idx];
                                  final bulbIndex = int.parse(bulbIdx) ?? 0;
        
        
                                  // 2) Parse interval text exactly once:
                                  final text = intervalMatrix.text.trim();
                                  final msInput = int.tryParse(text) ?? 0;
        
                                  // 3) Compute hi/lo _before_ building the list:
                                  final hi = (msInput >> 8) & 0xFF;   // high byte
                                  final lo = msInput & 0xFF;          // low  byte
        
                                  // 4) Build a true List<int> of length 6
                                  final cmd = <int>[
                                    3,          // your blink‐mode
                                    rgb[0],     // R
                                    rgb[1],     // G
                                    rgb[2],     // B
                                    hi,         // interval high byte
                                    lo,
                                    bulbIndex// interval low  byte
                                  ];
        
                                  print("🔵 Sending command: $cmd");  // debug, should show 6 items
                                  transmeter_logic.connectionControll.sendCommand(cmd);
                                },
                                    onLongPress: (){
                                      final cmd = <int>[
                                        0,          // your blink‐mode
                                        0,     // R
                                        0,     // G
                                        0,     // B
                                        hi,         // interval high byte
                                        lo          // interval low  byte
                                      ];
                                      transmeter_logic.connectionControll.sendCommand(cmd);
                                    },
                                    child: Text("Send"))
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
        
          ],
        ),
      ),
    );
  }
}
