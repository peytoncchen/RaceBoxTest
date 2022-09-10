//
//  BLEManager.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/7/22.
//

import Foundation
import CoreBluetooth

extension Data {
    func scanValue<T>(start: Int, length: Int) -> T {
        return self.subdata(in: start..<start+length).withUnsafeBytes { $0.pointee }
    }
}

extension CBPeripheral: Identifiable {
    public var id: UUID { return UUID() }
}

struct RaceBoxData {
    var iTow: UInt32 // c
    var Year: UInt16 // c
    var Month: Int8 // c
    var Day: Int8 // c
    var Hour: Int8 // c
    var Minute: Int8 // c
    var Second: Int8 // c
    var ValidityFlags: Int8 // c
    var TimeAccuracy: UInt32 // ignoring
    var Nanoseconds: Int32 // ignoring
    var FixStatus: Int8 // c
    var FixStatusFlags: Int8 // ignoring
    var DateTimeFlags: Int8 // ignoring
    var NumberOfSVs: Int8 // c
    var Longitude: Int32 // c
    var Latitude: Int32 // c
    var WGSAltitude: Int32 // c
    var MSLAltitude: Int32 // c
    var HorizontalAccuracy: UInt32 // ignoring
    var VerticalAccuracy: UInt32 // ignoring
    var Speed: Int32 // c
    var Heading: Int32 // c
    var SpeedAccuracy: UInt32 // ignoring
    var HeadingAccuracy: UInt32 // ignoring
    var PDOP: UInt16 // c
    var LatLongFlags: Int8 // ignoring
    var BatteryStatus: Int8 // c
    var GForceX: Int16 // c
    var GForceY: Int16 // c
    var GForceZ: Int16 // c
    var RotationRateX: Int16 // c
    var RotationRateY: Int16 // c
    var RotationRateZ: Int16 // c
}

struct ProcessedRaceBoxData {
    var iTow: UInt32
    var YearMonthDayHourMinuteSecond: String
    var FixStatus: String
    var ValidityFlags: String
    var NumberofSVs: Int8
    var Longitude: Int32
    var Latitude: Int32
    var WGSAltitude: Int32
    var MSLAltitude: Int32
    var Speed: Int32
    var Heading: Int32
    var PDOP: UInt16
    var BatteryCharging: Int8
    var BatteryLevel: Int8
    var GForceX: Int16
    var GForceY: Int16
    var GForceZ: Int16
    var RotationRateX: Int16
    var RotationRateY: Int16
    var RotationRateZ: Int16
}

let RaceBoxBLEServiceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
let RaceBoxBLETxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
let FULL_PAYLOAD_LENGTH = 80

class BLEManager: NSObject, ObservableObject {
    
    var central: CBCentralManager!
    @Published var connectedPeripheral: Optional<CBPeripheral> = nil
    @Published var peripherals = [CBPeripheral]()
    @Published var currentPacket: Optional<RaceBoxData> = nil
    @Published var peripheralRSSI: Optional<NSNumber> = nil
    
    var incompleteData = [Data]()
    
    override init() {
        super.init()

        central = CBCentralManager(delegate: self, queue: nil)
        central.delegate = self
    }
    
    func connectTo(peripheral: CBPeripheral) {
        central.connect(peripheral)
        connectedPeripheral = peripheral
        connectedPeripheral!.delegate = self
    }
    
    func disconnect() {
        if (connectedPeripheral != nil) {
            central.cancelPeripheralConnection(connectedPeripheral!)
            central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID], options: nil)
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID], options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (!peripherals.contains(peripheral)) {
            peripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral)")
        central.stopScan()
        connectedPeripheral!.discoverServices([RaceBoxBLEServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral)")
        connectedPeripheral = nil
        central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID], options: nil)
        currentPacket = nil
        peripheralRSSI = nil
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([RaceBoxBLETxCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print(characteristic)

            if characteristic.properties.contains(.notify) {
                print("\(characteristic.uuid): properties contains .notify")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        peripheralRSSI = RSSI
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case RaceBoxBLETxCharacteristicUUID:
            let data = gpsData(from: characteristic)
            if assertChecksum(gpsData: data) {
                if assertFrameStart(gpsData: data) && assertMsgClassAndId(gpsData: data) {
                    if readPayloadLength(gpsData: data) == FULL_PAYLOAD_LENGTH {
                        let payload = getPayload(gpsData: data, payloadLength: FULL_PAYLOAD_LENGTH)
                        let raceBoxData = parsePayload(payload: payload)
                        currentPacket = raceBoxData // Handle disconnect if lower than 5% battery
                    } else {
                        print("Incomplete packet received, handling...")
                        incompleteData.append(data)
                        var aggregatedLength = 0
                        for data in incompleteData {
                            aggregatedLength += Int(readPayloadLength(gpsData: data))
                        }
                        if aggregatedLength == FULL_PAYLOAD_LENGTH {
                            var aggregatedPayload = getPayload(gpsData: incompleteData[0], payloadLength: Int(readPayloadLength(gpsData: incompleteData[0])))
                            for data in incompleteData[1...] {
                                aggregatedPayload.append(contentsOf: getPayload(gpsData: data, payloadLength: Int(readPayloadLength(gpsData: data))))
                            }
                            let raceBoxData = parsePayload(payload: aggregatedPayload)
                            currentPacket = raceBoxData
                        }
                    }
                } else {
                    print("Frame start and/or Msg Class ID invalid")
                }
            } else {
                print("Invalid checksum, skipping packet")
            }
            
        default:
            print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        peripheral.readRSSI()
    }

    private func gpsData(from characteristic: CBCharacteristic) -> Data {
        guard let characteristicData = characteristic.value else { return Data() }
        return characteristicData
    }
}

extension BLEManager {
    
    private func assertFrameStart(gpsData: Data) -> Bool {
        return gpsData.scanValue(start: 0, length: 2) == 0x62B5
    }
    
    private func assertMsgClassAndId(gpsData: Data) -> Bool {
        return gpsData.scanValue(start: 2, length: 2) == 0x01FF
    }
    
    private func assertChecksum(gpsData: Data) -> Bool {
        var CK_A = 0
        var CK_B = 0
        for i in 2..<gpsData.count - 2 {
            CK_A += gpsData.scanValue(start: i, length: 1)
            CK_B += CK_A
        }
        return gpsData.scanValue(start: gpsData.count - 2, length: 1) == (CK_A & 0xFF) &&
            gpsData.scanValue(start: gpsData.count - 1, length: 1) == (CK_B & 0xFF)
    }
    
    private func readPayloadLength(gpsData: Data) -> UInt16 {
        return gpsData.scanValue(start: 4, length: 2)
    }
    
    private func getPayload(gpsData: Data, payloadLength: Int) -> Data {
        return gpsData.subdata(in: 6..<6+payloadLength)
    }
    
    private func parsePayload(payload: Data) -> RaceBoxData {
        return RaceBoxData(iTow: payload.scanValue(start: 0, length: 4),
                           Year: payload.scanValue(start: 4, length: 2),
                           Month: payload.scanValue(start: 6, length: 1),
                           Day: payload.scanValue(start: 7, length: 1),
                           Hour: payload.scanValue(start: 8, length: 1),
                           Minute: payload.scanValue(start: 9, length: 1),
                           Second: payload.scanValue(start: 10, length: 1),
                           ValidityFlags: payload.scanValue(start: 11, length: 1),
                           TimeAccuracy: payload.scanValue(start: 12, length: 4),
                           Nanoseconds: payload.scanValue(start: 16, length: 4),
                           FixStatus: payload.scanValue(start: 20, length: 1),
                           FixStatusFlags: payload.scanValue(start: 21, length: 1),
                           DateTimeFlags: payload.scanValue(start: 22, length: 1),
                           NumberOfSVs: payload.scanValue(start: 23, length: 1),
                           Longitude: payload.scanValue(start: 24, length: 4),
                           Latitude: payload.scanValue(start: 28, length: 4),
                           WGSAltitude: payload.scanValue(start: 32, length: 4),
                           MSLAltitude: payload.scanValue(start: 36, length: 4),
                           HorizontalAccuracy: payload.scanValue(start: 40, length: 4),
                           VerticalAccuracy: payload.scanValue(start: 44, length: 4),
                           Speed: payload.scanValue(start: 48, length: 4),
                           Heading: payload.scanValue(start: 52, length: 4),
                           SpeedAccuracy: payload.scanValue(start: 56, length: 4),
                           HeadingAccuracy: payload.scanValue(start: 60, length: 4),
                           PDOP: payload.scanValue(start: 64, length: 2),
                           LatLongFlags: payload.scanValue(start: 66, length: 1),
                           BatteryStatus: payload.scanValue(start: 67, length: 1),
                           GForceX: payload.scanValue(start: 68, length: 2),
                           GForceY: payload.scanValue(start: 70, length: 2),
                           GForceZ: payload.scanValue(start: 72, length: 2),
                           RotationRateX: payload.scanValue(start: 74, length: 2),
                           RotationRateY: payload.scanValue(start: 76, length: 2),
                           RotationRateZ: payload.scanValue(start: 78, length: 2))
    }
}

