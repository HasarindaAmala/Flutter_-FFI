import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class connectionController extends GetxController {
  // ------------------- STREAM CONTROLLERS -------------------
  late StreamController<bool>
  deviceBluetoothController; // (Not used in your code snippet)
  StreamSubscription<DiscoveredDevice>? scanSub;
  StreamSubscription<ConnectionStateUpdate>? connectSub;
  StreamSubscription<List<int>>? _notifySub;

  // ------------------- DEVICE & BLE TRACKING -------------------
  List<DiscoveredDevice> foundDevices = [];
  bool isBluetoothOn = false;
  String ConnectedId = "";
  bool RX_found = false;
  String deviceId = "";
  Uuid serviceWrite = Uuid([0x18, 0x19]);

  // ------------------- DATA / CALC FIELDS -------------------
  double Altitude = 0.0;
  double Velocity = 0.0;
  double distance_cal = 0.0;
  double distance = 0;

  // ------------------- STREAM CONTROLLERS FOR DATA -------------------
  late StreamController<bool> RxfoundController;
  late StreamController<List<double>> ValuesController;
  StreamController<String> connection = StreamController<String>.broadcast();
  // BLE-related
  late List<DiscoveredService> discoveredServices;
  late Uuid characteristicId;

  // Temp buffers for partial data
  List<int> completeMessage = [];
  List<int> cacheBuffer = [];
  List<int> finalResult = [];
  List<double> values = [];

  // Connectivity
  String connectionStatus = '';
  bool bluetoth_connected = false; // (Not used directly in the snippet)
  bool internetConnected = false;

  // The BLE instance
  final FlutterReactiveBle ble = FlutterReactiveBle();

  // ------------------- LIFECYCLE -------------------

  @override
  void onClose() {
    // Cancel any active streams/subscriptions
    connectSub?.cancel();
    scanSub?.cancel();
    _notifySub?.cancel();
    // Close the controllers if they exist
    RxfoundController.close();
    ValuesController.close();

    super.onClose();
  }

  // ------------------- CONNECTIVITY -------------------

  /// Checks the device's connectivity (Wi-Fi, mobile, none) and updates [connectionStatus] & [internetConnected].
  /// Calls update() so that GetBuilder widgets can rebuild if needed.
  Future<void> checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    print("connectivityResult: $connectivityResult");

    switch (connectivityResult) {
      case ConnectivityResult.wifi:
        connectionStatus = 'Wi-Fi';
        internetConnected = true;
        break;
      case ConnectivityResult.mobile:
        connectionStatus = 'Cellular';
        internetConnected = true;
        break;
      case ConnectivityResult.none:
        connectionStatus = 'Not connected';
        internetConnected = false;
        break;
      default:
        connectionStatus = 'Unknown';
        internetConnected = false;
        break;
    }

    print(connectionStatus);
    update(); // Notify UI
  }

  // ------------------- BLUETOOTH PERMISSIONS -------------------

  /// Requests Bluetooth permissions for Android 12+ or iOS as needed.
  /// On permanent denial, opens App Settings.

  Future<void> requestBluetoothPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      final scanStatus =
          statuses[Permission.bluetoothScan] ?? PermissionStatus.denied;
      final connectStatus =
          statuses[Permission.bluetoothConnect] ?? PermissionStatus.denied;
      final advertiseStatus =
          statuses[Permission.bluetoothAdvertise] ?? PermissionStatus.denied;

      if (scanStatus.isPermanentlyDenied ||
          connectStatus.isPermanentlyDenied ||
          advertiseStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
    } else if (Platform.isIOS) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      // On iOS, just make sure you have this key in Info.plist:
      // NSBluetoothAlwaysUsageDescription
      // System will auto-prompt when Bluetooth API is accessed
      // You may optionally open settings if certain APIs fail
    }
  }

  // ------------------- BLUETOOTH ENABLED CHECK -------------------

  /// Subscribes to the BLE status stream. If status is `BleStatus.ready`, [isBluetoothOn] = true; else false.
  void isEnableBluetooth() {
    ble.statusStream.listen((status) {
      if (status == BleStatus.ready) {
        isBluetoothOn = true;
      } else {
        isBluetoothOn = false;
      }
      update(); // Rebuild UI if needed
    });
  }

  // ------------------- SCANNING -------------------

  /// Starts a new BLE scan. Clears the previous [foundDevices], requests permissions, and listens for discovered devices.
  Future<void> startScan() async {
    print("Start scan");
    await requestBluetoothPermissions();

    // Cancel any previous scan
    await scanSub?.cancel();
    foundDevices.clear();
    update();

    scanSub = ble.scanForDevices(withServices: []).listen((device) {
      if (!foundDevices.any((d) => d.id == device.id) &&
          device.name.isNotEmpty) {
        foundDevices.add(device);
        print("device: $device");
        update();
      }
    }, onError: (error) {
      if (error is GenericFailure<ScanFailure>) {
        print(
            "Scan failed with code: ${error.code}, message: ${error.message}");
        // You could handle retry logic here
      }
    });
  }

  // ------------------- CONNECT TO DEVICE -------------------

  /// Connects to [foundDeviceId], sets up a subscription to handle states, and attempts to discover & subscribe to characteristics.
  Future<void> connectToDevice(
      String foundDeviceId, DiscoveredDevice device) async {
    connectSub?.cancel(); // Cancel any existing connection attempt
    update();
    await Future.delayed(const Duration(seconds: 1));
    connectSub = ble
        .connectToDevice(
      id: foundDeviceId,
      connectionTimeout: const Duration(seconds: 30),
    )
        .listen((connectionState) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        print("connected");
        connection.sink.add("connected");
        RX_found = true;
        RxfoundController.sink.add(RX_found);
        update();

        Uuid service =
            device.serviceUuids.first; // First service from the device
        //getChar(device.id, service);
        ConnectedId = foundDeviceId;
        update();

      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        print("disconnected listner");
        ConnectedId = "";
        RX_found = false;
        connection.sink.add("disconnected");
        RxfoundController.sink.add(RX_found);
        update();

        // Attempt auto-reconnect if you want:
        // connectToDevice(foundDeviceId, device);
      } else if (connectionState.connectionState ==
          DeviceConnectionState.connecting) {
        // connecting or disconnecting states
        connection.sink.add("connecting");
      }
    }, onError: (Object error) {
      // Handle a possible error
      connection.sink.add("error");
      print("connectToDevice error: $error");
    });
  }

  // ------------------- DISCOVER CHARACTERISTICS -------------------

  /// Discovers services in [deviceId], picks the first characteristic from [Service], and subscribes to notifications.
  void getChar(String deviceId, Uuid Service) async {
    deviceId = deviceId;
    Service = Service;
    update();
    discoveredServices = await ble.discoverServices(deviceId);

    // Find the correct characteristic in the discovered services
    for (var service in discoveredServices) {
      print("Service characteristics: ${service.characteristics}");

      if (service.serviceId == Service) {
        characteristicId = Uuid([0x2a, 0x4d]);
        update();
        print("Char uuid :$characteristicId");
      }
    }

    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Service,
      characteristicId: characteristicId,
    );

    // Cancel previous notifications, if any
    _notifySub?.cancel();

    // Subscribe to notifications on this characteristic
    _notifySub = ble.subscribeToCharacteristic(characteristic).listen((data) {
      // parse data


    }, onError: (dynamic error) {
      // Handle notify errors
      print("Notification error: $error");
    });
  }

// // To write a command (e.g. [0xA1, 0x01]):
  void sendCommand(data) async {
    final characteristicWrite = QualifiedCharacteristic(
      deviceId: ConnectedId,
      serviceId: serviceWrite,
      characteristicId: Uuid([0x2b, 0x1e]),
    );
    try {
      await ble.writeCharacteristicWithResponse(characteristicWrite,
          value: data);
      print("✅ Command sent: $data");
    } catch (e) {
      print("❌ Failed to send BLE command: $e");
    }
  }

  // ------------------- DISCONNECT -------------------

  /// Cancels active connections and scans, resets flags, and notifies UI.
  Future<void> disconnect() async {
    RX_found = false;
    RxfoundController.sink.add(RX_found);
    update();
    await connectSub?.cancel();
    await scanSub?.cancel();
    ConnectedId = "";
    values.clear();
    ValuesController.sink.add([]);
    connection.sink.add("disconnected");
    print("disconnected from function");
    update();
  }


  // ------------------- BYTES -> NUMBERS -------------------

  double bytesToDouble(List<int> byteArray) {
    if (byteArray.length != 8) {
      throw ArgumentError('Byte array must be exactly 8 bytes long');
    }
    Uint8List uint8List = Uint8List.fromList(byteArray);
    ByteData byteData = ByteData.sublistView(uint8List);
    return byteData.getFloat64(0, Endian.little);
  }

  int bytesToInt16(List<int> byteArray, Endian endian) {
    if (byteArray.length != 2) {
      print("byte size :${byteArray.length}");
      throw ArgumentError('Byte array must be exactly 2 bytes long');
    }
    Uint8List uint8List = Uint8List.fromList(byteArray);
    ByteData byteData = ByteData.sublistView(uint8List);
    return byteData.getInt16(0, endian);
  }

  int bytesToInt32(List<int> byteArray, Endian endian) {
    if (byteArray.length != 4) {
      throw ArgumentError('Byte array must be exactly 4 bytes long');
    }
    Uint8List uint8List = Uint8List.fromList(byteArray);
    ByteData byteData = ByteData.sublistView(uint8List);
    return byteData.getInt32(0, endian);
  }

  double bytesToFloat32(List<int> byteArray, Endian endian) {
    if (byteArray.length != 4) {
      throw ArgumentError('Byte array must be exactly 4 bytes long');
    }
    Uint8List uint8List = Uint8List.fromList(byteArray);
    ByteData byteData = ByteData.sublistView(uint8List);
    return byteData.getFloat32(0, endian);
  }

  // ------------------- DISTANCE CALC -------------------



}