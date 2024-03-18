import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:win32/win32.dart';
import 'package:win_ble/win_ble.dart';
import 'package:win_ble/win_file.dart';

import 'print_data.dart';
import 'printers_data.dart';

class WindowBleManager {
  WindowBleManager._privateConstructor();

  static WindowBleManager? _instance;

  static WindowBleManager get instance {
    _instance ??= WindowBleManager._privateConstructor();
    return _instance!;
  }

  static bool isInitialized = false;

  static init() async {
    if (!isInitialized) {
      WinBle.initialize(serverPath: await WinServer.path()).then((value) {
        isInitialized = true;
      });
    }
  }

  final StreamController<List<Printer>> _devicesstream =
      StreamController<List<Printer>>.broadcast();

  Stream<List<Printer>> get devicesStream => _devicesstream.stream;

  // Stop scanning for BLE devices
  Future<void> stopscan() async {
    if (!isInitialized) {
      throw Exception('WindowBluetoothManager is not initialized');
    }
    WinBle.stopScanning();
    subscription?.cancel();
  }

  StreamSubscription? subscription;

  // Find all BLE devices
  Future<void> startscan() async {
    if (!isInitialized) {
      log("Init");
      await init();
    }
    if (!isInitialized) {
      throw Exception(
        'WindowBluetoothManager is not initialized. Try starting the scan again',
      );
    }
    List<Printer> devices = [];
    WinBle.startScanning();
    subscription = WinBle.scanStream.listen((device) async {
      log(device.name);
      devices.add(Printer(
        address: device.address,
        name: device.name,
        connectionType: ConnectionType.BLE,
        isConnected: await WinBle.isPaired(device.address),
        // isConnected: false,
      ));
    });
  }

  // Connect to a BLE device
  Future<bool> connect(Printer device) async {
    if (!isInitialized) {
      throw Exception('WindowBluetoothManager is not initialized');
    }
    bool isConnected = false;
    final subscription = WinBle.connectionStream.listen((device) {});
    await WinBle.connect(device.address!);
    await Future.delayed(const Duration(seconds: 3));
    subscription.cancel();
    return isConnected;
  }

  // Print data to a BLE device
  Future<void> printData(
    Printer device,
    List<int> bytes, {
    bool longData = false,
  }) async {
    if (device.connectionType == ConnectionType.USB) {
      using((Arena alloc) {
        final printer = RawPrinter(device.name!, alloc);
        final data = <String>[
          '''Dekha hazaro dafa aapko
Phir bekarari kaisi hai
Sambhale sambhalta nahi yeh dil
Kuch pyaar mein baat aisi hai

Lekar ijazat ab aap se
Saansein yeh aati jati hain
Dhoondhe se milte nahi hai hum
Bas aap hi aap baki hain

Pal bhar na doori sahe aap se
Betabiyan yeh kuch aur hain
Hum door ho ke bhi paas hain
Nazdeekiyan yeh kuch aur hain

Dekha hazaro dafaa aapko
Phir bekarari kaisi hai
Sambhale sambhalta nahi ye dil
Kuch pyar mein baat aisi hai

Aagosh mein hain jo aapki
Aisa sukun aur paaye kahaan
Aankhein hamein raas aa gayi
Ab hum yahaan se jaaye kahan

Dekha hazaron dafa aapko
Phir bekarari kaisi hai
Sambhale sambhalta nahi ye dil
Kuch pyaar mein baat aisi hai

Phir bekarari kaisi hai
Kuch pyaar mein baat aisi hai'''
        ];

        if (printer.printLines(data)) {
          log('Success!');
        }
      });
      return;
    }
    if (!isInitialized) {
      throw Exception('WindowBluetoothManager is not initialized');
    }
    final services = await WinBle.discoverServices(device.address!);
    final service = services.first;
    final characteristics = await WinBle.discoverCharacteristics(
      address: device.address!,
      serviceId: service,
    );
    final characteristic = characteristics
        .firstWhere((element) => element.properties.write ?? false)
        .uuid;
    final mtusize = await WinBle.getMaxMtuSize(device.address!);
    if (longData) {
      int mtu = mtusize - 50;
      if (mtu.isNegative) {
        mtu = 20;
      }
      final numberOfTimes = bytes.length / mtu;
      final numberOfTimesInt = numberOfTimes.toInt();
      int timestoPrint = 0;
      if (numberOfTimes > numberOfTimesInt) {
        timestoPrint = numberOfTimesInt + 1;
      } else {
        timestoPrint = numberOfTimesInt;
      }
      for (var i = 0; i < timestoPrint; i++) {
        final data = bytes.sublist(i * mtu,
            ((i + 1) * mtu) > bytes.length ? bytes.length : ((i + 1) * mtu));
        await WinBle.write(
          address: device.address!,
          service: service,
          characteristic: characteristic,
          data: Uint8List.fromList(data),
          writeWithResponse: false,
        );
      }
    } else {
      await WinBle.write(
        address: device.address!,
        service: service,
        characteristic: characteristic,
        data: Uint8List.fromList(bytes),
        writeWithResponse: false,
      );
    }
  }

  StreamSubscription? _usbSubscription;

  // Getprinters
  void getPrinters({
    Duration refreshDuration = const Duration(seconds: 5),
    List<ConnectionType> connectionTypes = const [
      ConnectionType.BLE,
      ConnectionType.USB,
    ],
  }) async {
    List<Printer> btlist = [];
    if (connectionTypes.contains(ConnectionType.BLE)) {}
    List<Printer> list = [];
    if (connectionTypes.contains(ConnectionType.USB)) {
      _usbSubscription?.cancel();
      _usbSubscription =
          Stream.periodic(refreshDuration, (x) => x).listen((event) async {
        final devices = PrinterNames(PRINTER_ENUM_LOCAL);
        List<Printer> templist = [];
        for (var e in devices.all()) {
          final device = Printer(
            vendorId: e,
            productId: "N/A",
            name: e,
            connectionType: ConnectionType.USB,
            address: e,
            isConnected: true,
          );
          templist.add(device);
        }
        list = templist;
      });
    }
    Stream.periodic(refreshDuration, (x) => x).listen((event) {
      _devicesstream.add(list + btlist);
    });
  }
}
