//
//  RaceBoxManager.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/7/22.
//

import Foundation
import CoreBluetooth
import CoreMotion

// Sneaky way to silence the deprecation warning
// Need to use as (data as DataWithScan).scanValue(...)
// It wants to type the return value from withUnsafeBytes but
// the whole point is to not... so decided to just silence it.
private protocol DataWithScan {
    func scanValue<T>(start: Int, length: Int) -> T
}

extension Data: DataWithScan {
    @available(iOS, deprecated: 12.2)
    func scanValue<T>(start: Int, length: Int) -> T {
        return self.subdata(in: start..<start+length).withUnsafeBytes { $0.pointee }
    }
}

class RaceBoxManager: NSObject, ObservableObject {
    
    // Central
    @Published var peripherals = [CBPeripheral]()
    private var central: CBCentralManager!
    
    // Peripheral
    @Published var connectedPeripheral: Optional<CBPeripheral> = nil
    @Published var peripheralRSSI: Optional<NSNumber> = nil
    @Published var connecting = false
    
    // Peripheral Data
    @Published var currentPacket: Optional<ProcessedRaceBoxData> = nil
    @Published var peripheralSerialNumber: Optional<String> = nil
    private var incompleteData = [Data]()
    
    // Peripheral Battery Level
    // For whatever reason if you disconnect and reconnect the RaceBox,
    // the first battery level reading to come through is 0%... which is a problem
    // because we check if it's less than or equal to 2% and ask to disconnect.
    // I solve this by skipping the first reading.
    private var batteryStatus: UInt = 100
    private var isFirstBatteryLevelRead = true
    
    // To measure Hz
    var startTime: TimeInterval!
    var packetCount = 0
    @Published var Hz: Double = 0.0
    
    override init() {
        super.init()

        central = CBCentralManager(delegate: self, queue: nil)
        central.delegate = self
    }
    
    func connectTo(peripheral: CBPeripheral) {
        central.connect(peripheral)
        connecting = true
    }
    
    func disconnect() {
        if (connectedPeripheral != nil) {
            central.cancelPeripheralConnection(connectedPeripheral!)
        }
    }
}

// -- CentralManager Functions
extension RaceBoxManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID, RaceBoxBLEDeviceInfoServiceUUID], options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if ((name != nil) && name!.starts(with: "RaceBox Mini")) && !peripherals.contains(peripheral) {
            peripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral)")
        connecting = false
        connectedPeripheral = peripheral
        connectedPeripheral!.delegate = self
        connectedPeripheral!.discoverServices([RaceBoxBLEServiceUUID, RaceBoxBLEDeviceInfoServiceUUID])
        central.stopScan()
        peripherals.removeAll()
        packetCount = 0
        startTime = (NSDate.timeIntervalSinceReferenceDate)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral)")
        connectedPeripheral = nil
        central.scanForPeripherals(withServices: [RaceBoxBLEServiceUUID, RaceBoxBLEDeviceInfoServiceUUID], options: nil)
        currentPacket = nil
        peripheralRSSI = nil
        peripheralSerialNumber = nil
        isFirstBatteryLevelRead = true
        Hz = 0.0
    }
}

// -- Peripheral Functions
extension RaceBoxManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        print(services)
        for service in services {
            peripheral.discoverCharacteristics([RaceBoxBLETxCharacteristicUUID, RaceBoxBLESerialNumberCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print(characteristic)
            if characteristic.properties.contains(.read) {
                print("\(characteristic.uuid): properties contains .read")
                peripheral.readValue(for: characteristic)
            }
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
                        handlePayload(payload: payload)
                        packetCount += 1
                        let elapsed = (NSDate.timeIntervalSinceReferenceDate) - startTime
                        Hz = Double(packetCount) / elapsed
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
                            incompleteData.removeAll()
                            print("Incomplete packets reconstructed, handling...")
                            packetCount += 1
                            let elapsed = (NSDate.timeIntervalSinceReferenceDate) - startTime
                            Hz = Double(packetCount) / elapsed
                        }
                    }
                } else {
                    print("Frame start and/or Msg Class ID invalid")
                }
            } else {
                print("Invalid checksum, skipping packet")
            }
            
        case RaceBoxBLESerialNumberCharacteristicUUID:
            let serialNumber = deviceInfo(from: characteristic)
            peripheralSerialNumber = serialNumber
            
        default:
            print("Unhandled Characteristic UUID: \(characteristic.uuid)")
        }
        peripheral.readRSSI()
    }
}

// -- Private data-handling functions
extension RaceBoxManager {
    private func gpsData(from characteristic: CBCharacteristic) -> Data {
        guard let characteristicData = characteristic.value else { return Data() }
        return characteristicData
    }
    
    private func deviceInfo(from characteristic: CBCharacteristic) -> String {
      guard let characteristicData = characteristic.value else { return "Error fetching Device Info" }
        return String(decoding: characteristicData, as: UTF8.self)
    }
    
    private func handlePayload(payload: Data) {
        let raceBoxData = parsePayload(payload: payload)
        let processedRaceBoxData = processRaceBoxData(raceBoxData: raceBoxData)
        currentPacket = processedRaceBoxData
        
        if !isFirstBatteryLevelRead && processedRaceBoxData.batteryLevel <= 2 {
            print("disconnecting because battery is at 2%")// disconnect if less than 2 percent
            disconnect()
        }
        if isFirstBatteryLevelRead {
            isFirstBatteryLevelRead = true
        }
    }
    
    private func assertFrameStart(gpsData: Data) -> Bool {
        return (gpsData as DataWithScan).scanValue(start: 0, length: 2) == 0x62b5
    }
    
    private func assertMsgClassAndId(gpsData: Data) -> Bool {
        return (gpsData as DataWithScan).scanValue(start: 2, length: 2) == 0x01ff
    }
    
    private func assertChecksum(gpsData: Data) -> Bool {
        var CK_A = 0
        var CK_B = 0
        for i in 2..<gpsData.count - 2 {
            CK_A += (gpsData as DataWithScan).scanValue(start: i, length: 1)
            CK_B += CK_A
        }
        return (gpsData as DataWithScan).scanValue(start: gpsData.count - 2, length: 1) == (CK_A & 0xff) &&
        (gpsData as DataWithScan).scanValue(start: gpsData.count - 1, length: 1) == (CK_B & 0xff)
    }
    
    private func readPayloadLength(gpsData: Data) -> UInt16 {
        return (gpsData as DataWithScan).scanValue(start: 4, length: 2)
    }
    
    private func getPayload(gpsData: Data, payloadLength: Int) -> Data {
        return gpsData.subdata(in: 6..<6+payloadLength)
    }
    
    private func parsePayload(payload: Data) -> RaceBoxData {
        return RaceBoxData(iTow: (payload as DataWithScan).scanValue(start: 0, length: 4),
                           year: (payload as DataWithScan).scanValue(start: 4, length: 2),
                           month: (payload as DataWithScan).scanValue(start: 6, length: 1),
                           day: (payload as DataWithScan).scanValue(start: 7, length: 1),
                           hour: (payload as DataWithScan).scanValue(start: 8, length: 1),
                           minute: (payload as DataWithScan).scanValue(start: 9, length: 1),
                           second: (payload as DataWithScan).scanValue(start: 10, length: 1),
                           validityFlags: (payload as DataWithScan).scanValue(start: 11, length: 1),
                           timeAccuracy: (payload as DataWithScan).scanValue(start: 12, length: 4),
                           nanoseconds: (payload as DataWithScan).scanValue(start: 16, length: 4),
                           fixStatus: (payload as DataWithScan).scanValue(start: 20, length: 1),
                           fixStatusFlags: (payload as DataWithScan).scanValue(start: 21, length: 1),
                           dateTimeFlags: (payload as DataWithScan).scanValue(start: 22, length: 1),
                           numberOfSVs: (payload as DataWithScan).scanValue(start: 23, length: 1),
                           longitude: (payload as DataWithScan).scanValue(start: 24, length: 4),
                           latitude: (payload as DataWithScan).scanValue(start: 28, length: 4),
                           wgsAltitude: (payload as DataWithScan).scanValue(start: 32, length: 4),
                           mslAltitude: (payload as DataWithScan).scanValue(start: 36, length: 4),
                           horizontalAccuracy: (payload as DataWithScan).scanValue(start: 40, length: 4),
                           verticalAccuracy: (payload as DataWithScan).scanValue(start: 44, length: 4),
                           speed: (payload as DataWithScan).scanValue(start: 48, length: 4),
                           heading: (payload as DataWithScan).scanValue(start: 52, length: 4),
                           speedAccuracy: (payload as DataWithScan).scanValue(start: 56, length: 4),
                           headingAccuracy: (payload as DataWithScan).scanValue(start: 60, length: 4),
                           pdop: (payload as DataWithScan).scanValue(start: 64, length: 2),
                           latLongFlags: (payload as DataWithScan).scanValue(start: 66, length: 1),
                           batteryStatus: (payload as DataWithScan).scanValue(start: 67, length: 1),
                           gForceX: (payload as DataWithScan).scanValue(start: 68, length: 2),
                           gForceY: (payload as DataWithScan).scanValue(start: 70, length: 2),
                           gForceZ: (payload as DataWithScan).scanValue(start: 72, length: 2),
                           rotationRateX: (payload as DataWithScan).scanValue(start: 74, length: 2),
                           rotationRateY: (payload as DataWithScan).scanValue(start: 76, length: 2),
                           rotationRateZ: (payload as DataWithScan).scanValue(start: 78, length: 2))
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
    
    private func determineValidityFlags(validityFlags: UInt) -> String {
        var result = ""
        if validityFlags & 0x1 == 1 {
            result += "valid date\n"
        }
        if (validityFlags >> 1) & 0x1 == 1 {
            result += "valid time\n"
        }
        if (validityFlags >> 2) & 0x1 == 1 {
            result += "fully resolved\n"
        }
        if (validityFlags >> 3) & 0x1 == 1 {
            result += "valid magnetic declination\n"
        }
        if result == "" {
            return "all validity flags false\n"
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
                                    validityFlags: determineValidityFlags(validityFlags: UInt(raceBoxData.validityFlags)),
                                    numberofSVs: Int(raceBoxData.numberOfSVs),
                                    longitude: Double(raceBoxData.longitude) * 1e-7,
                                    latitude: Double(raceBoxData.latitude) * 1e-7,
                                    wgsAltitude: Double(raceBoxData.wgsAltitude) * 1e-3 * 3.280839895,
                                    speed: Double(raceBoxData.speed) * 0.00223693629,
                                    heading: Double(raceBoxData.heading) * 1e-5,
                                    batteryCharging: UInt(raceBoxData.batteryStatus) >> 7 == 1,
                                    batteryLevel: UInt(raceBoxData.batteryStatus) & 0x7f,
                                    gForceX: Double(raceBoxData.gForceX) / 1000,
                                    gForceY: Double(raceBoxData.gForceY) / 1000,
                                    gForceZ: Double(raceBoxData.gForceZ) / 1000,
                                    rotationRateX: Double(raceBoxData.rotationRateX) / 100,
                                    rotationRateY: Double(raceBoxData.rotationRateY) / 100,
                                    rotationRateZ: Double(raceBoxData.rotationRateZ) / 100)
    }
}

