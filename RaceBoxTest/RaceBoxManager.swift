//
//  RaceBoxManager.swift
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
    var iTow: UInt32
    var year: UInt16
    var month: Int8
    var day: Int8
    var hour: Int8
    var minute: Int8
    var second: Int8
    var validityFlags: Int8
    var timeAccuracy: UInt32 // ignoring
    var nanoseconds: Int32 // ignoring
    var fixStatus: Int8
    var fixStatusFlags: Int8 // ignoring
    var dateTimeFlags: Int8 // ignoring
    var numberOfSVs: Int8
    var longitude: Int32
    var latitude: Int32
    var wgsAltitude: Int32
    var mslAltitude: Int32
    var horizontalAccuracy: UInt32 // ignoring
    var verticalAccuracy: UInt32 // ignoring
    var speed: Int32
    var heading: Int32
    var speedAccuracy: UInt32 // ignoring
    var headingAccuracy: UInt32 // ignoring
    var pdop: UInt16
    var latLongFlags: Int8 // ignoring
    var batteryStatus: Int8
    var gForceX: Int16
    var gForceY: Int16
    var gForceZ: Int16
    var rotationRateX: Int16
    var rotationRateY: Int16
    var rotationRateZ: Int16
}

struct ProcessedRaceBoxData {
    var date: Date
    var fixStatus: String
    var validityFlags: String
    var numberofSVs: Int
    var longitude: Float
    var latitude: Float
    var wgsAltitude: Float // converted from mm -> ft
    var speed: Float // converted from mm/s -> mph
    var heading: Float
    var batteryCharging: Bool
    var batteryLevel: Int
    var gForceX: Float
    var gForceY: Float
    var gForceZ: Float
    var rotationRateX: Float
    var rotationRateY: Float
    var rotationRateZ: Float
}

let RaceBoxBLEServiceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
let RaceBoxBLETxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
let FULL_PAYLOAD_LENGTH = 80

class RaceBoxManager: NSObject, ObservableObject {
    
    var central: CBCentralManager!
    var timer: Timer!
    @Published var connectedPeripheral: Optional<CBPeripheral> = nil
    @Published var peripherals = [CBPeripheral]()
    @Published var currentPacket: Optional<ProcessedRaceBoxData> = nil
    @Published var peripheralRSSI: Optional<NSNumber> = nil
    
    var incompleteData = [Data]()
    var batteryStatus = 100
    
    override init() {
        super.init()

        central = CBCentralManager(delegate: self, queue: nil)
        central.delegate = self
        
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { _ in
            self.checkBatteryStatus()
        })
    }
    
    func connectTo(peripheral: CBPeripheral) {
        central.connect(peripheral)
    }
    
    func disconnect() {
        if (connectedPeripheral != nil) {
            central.cancelPeripheralConnection(connectedPeripheral!)
        }
    }
    
    private func checkBatteryStatus(){
        print("Checking battery...")
        if batteryStatus <= 2 { // disconnect if less than 2 percent
            disconnect()
        }
    }
}

extension RaceBoxManager: CBCentralManagerDelegate {
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
        connectedPeripheral = peripheral
        connectedPeripheral!.delegate = self
        connectedPeripheral!.discoverServices([RaceBoxBLEServiceUUID])
        central.stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral)")
        connectedPeripheral = nil
        central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID], options: nil)
        currentPacket = nil
        peripheralRSSI = nil
    }
}

extension RaceBoxManager: CBPeripheralDelegate {
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
    
    private func handlePayload(payload: Data) {
        let raceBoxData = parsePayload(payload: payload)
        let processedRaceBoxData = processRaceBoxData(raceBoxData: raceBoxData)
        currentPacket = processedRaceBoxData
        
        if processedRaceBoxData.batteryLevel != batteryStatus { // Disconnect if lower than 2% battery
            batteryStatus = processedRaceBoxData.batteryLevel
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case RaceBoxBLETxCharacteristicUUID:
            let data = gpsData(from: characteristic)
            if assertChecksum(gpsData: data) {
                if assertFrameStart(gpsData: data) && assertMsgClassAndId(gpsData: data) {
                    if readPayloadLength(gpsData: data) == FULL_PAYLOAD_LENGTH {
                        let payload = getPayload(gpsData: data, payloadLength: FULL_PAYLOAD_LENGTH)
                        handlePayload(payload: payload)
                        
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
                            handlePayload(payload: aggregatedPayload)
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

extension RaceBoxManager {
    
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
                           year: payload.scanValue(start: 4, length: 2),
                           month: payload.scanValue(start: 6, length: 1),
                           day: payload.scanValue(start: 7, length: 1),
                           hour: payload.scanValue(start: 8, length: 1),
                           minute: payload.scanValue(start: 9, length: 1),
                           second: payload.scanValue(start: 10, length: 1),
                           validityFlags: payload.scanValue(start: 11, length: 1),
                           timeAccuracy: payload.scanValue(start: 12, length: 4),
                           nanoseconds: payload.scanValue(start: 16, length: 4),
                           fixStatus: payload.scanValue(start: 20, length: 1),
                           fixStatusFlags: payload.scanValue(start: 21, length: 1),
                           dateTimeFlags: payload.scanValue(start: 22, length: 1),
                           numberOfSVs: payload.scanValue(start: 23, length: 1),
                           longitude: payload.scanValue(start: 24, length: 4),
                           latitude: payload.scanValue(start: 28, length: 4),
                           wgsAltitude: payload.scanValue(start: 32, length: 4),
                           mslAltitude: payload.scanValue(start: 36, length: 4),
                           horizontalAccuracy: payload.scanValue(start: 40, length: 4),
                           verticalAccuracy: payload.scanValue(start: 44, length: 4),
                           speed: payload.scanValue(start: 48, length: 4),
                           heading: payload.scanValue(start: 52, length: 4),
                           speedAccuracy: payload.scanValue(start: 56, length: 4),
                           headingAccuracy: payload.scanValue(start: 60, length: 4),
                           pdop: payload.scanValue(start: 64, length: 2),
                           latLongFlags: payload.scanValue(start: 66, length: 1),
                           batteryStatus: payload.scanValue(start: 67, length: 1),
                           gForceX: payload.scanValue(start: 68, length: 2),
                           gForceY: payload.scanValue(start: 70, length: 2),
                           gForceZ: payload.scanValue(start: 72, length: 2),
                           rotationRateX: payload.scanValue(start: 74, length: 2),
                           rotationRateY: payload.scanValue(start: 76, length: 2),
                           rotationRateZ: payload.scanValue(start: 78, length: 2))
    }
    
    private func determineFixStatus(fixStatus: Int) -> String {
        switch fixStatus {
            case 0:
                return "no fix"
            case 2:
                return "2D fix"
            case 3:
                return "3D fix"
            default:
                return "Error parsing fix status value"
        }
    }
    
    private func determineValidityFlags(validityFlags: Int) -> String {
        var result = ""
        if validityFlags & 0x1 == 1 {
            result += "valid date "
        }
        if validityFlags & 0x10 == 1 {
            result += "valid time "
        }
        if validityFlags & 0x100 == 1 {
            result += "fully resolved "
        }
        if validityFlags & 0x1000 == 1 {
            result += "valid magnetic declination "
        }
        if result == "" {
            return "all validity flags false"
        }
        return result
    }
    
    private func processRaceBoxData(raceBoxData: RaceBoxData) -> ProcessedRaceBoxData {
        let calendar = Calendar(identifier: .gregorian)
        let dateComponents = DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                           year: Int(raceBoxData.year),
                                           month: Int(raceBoxData.month),
                                           day: Int(raceBoxData.day),
                                           hour: Int(raceBoxData.hour),
                                           minute: Int(raceBoxData.minute),
                                           second: Int(raceBoxData.second),
                                           nanosecond: Int(raceBoxData.nanoseconds))
        let currentDate = calendar.date(from: dateComponents)!
        return ProcessedRaceBoxData(date: currentDate,
                                    fixStatus: determineFixStatus(fixStatus: Int(raceBoxData.fixStatus)),
                                    validityFlags: determineValidityFlags(validityFlags: Int(raceBoxData.validityFlags)),
                                    numberofSVs: Int(raceBoxData.numberOfSVs),
                                    longitude: Float(raceBoxData.longitude) * 1e-7,
                                    latitude: Float(raceBoxData.latitude) * 1e-7,
                                    wgsAltitude: Float(raceBoxData.wgsAltitude) * 1e-3 * 3.28084,
                                    speed: Float(raceBoxData.speed) * 0.00223694,
                                    heading: Float(raceBoxData.heading) * 1e-5,
                                    batteryCharging: Int(raceBoxData.batteryStatus) & 0x80 == 1,
                                    batteryLevel: Int(raceBoxData.batteryStatus) & 0x7F,
                                    gForceX: Float(raceBoxData.gForceX) / 1000,
                                    gForceY: Float(raceBoxData.gForceY) / 1000,
                                    gForceZ: Float(raceBoxData.gForceZ) / 1000,
                                    rotationRateX: Float(raceBoxData.rotationRateX) / 100,
                                    rotationRateY: Float(raceBoxData.rotationRateY) / 100,
                                    rotationRateZ: Float(raceBoxData.rotationRateZ) / 100)
    }
}

