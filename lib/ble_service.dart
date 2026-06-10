import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String deviceName = 'SmartPen';
  static const String serviceUUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String characteristicUUID = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  bool _connected = false;

  bool get isConnected => _connected;

  // scan and connect to SmartPen
  Future<bool> connect() async {
    try {
      // check if bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        print('Bluetooth is off');
        return false;
      }

      // scan and connect in one step
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      await for (final results in FlutterBluePlus.scanResults) {
        for (final result in results) {
          print('Found device: ${result.device.platformName}');
          if (result.device.platformName == deviceName) {
            await FlutterBluePlus.stopScan();
            _device = result.device;

            // connect immediately while device is fresh in scan
            await _device!.connect(
              timeout: const Duration(seconds: 15),
              autoConnect: false,
            );
            print('Connected to SmartPen');

            // discover services
            final services = await _device!.discoverServices();
            for (final service in services) {
              if (service.serviceUuid.toString().toLowerCase() == serviceUUID) {
                for (final characteristic in service.characteristics) {
                  if (characteristic.characteristicUuid.toString().toLowerCase() == characteristicUUID) {
                    _characteristic = characteristic;
                    _connected = true;
                    print('Characteristic found — BLE ready');
                    return true;
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('BLE connect error: $e');
    }
    return false;
  }

  // send haptic command
  Future<void> sendCommand(String command) async {
    if (!_connected || _characteristic == null) {
      print('MOCK BLE: $command (not connected)');
      return;
    }
    try {
      await _characteristic!.write(command.codeUnits, withoutResponse: false);
      print('BLE sent: $command');
    } catch (e) {
      print('BLE send error: $e');
      _connected = false;
    }
  }

  // disconnect
  Future<void> disconnect() async {
    await _device?.disconnect();
    _connected = false;
    _characteristic = null;
    print('Disconnected from SmartPen');
  }
}