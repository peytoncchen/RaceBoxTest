//
//  RaceBoxBluetooth.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/13/22.
//

import Foundation
import CoreBluetooth

extension CBPeripheral: Identifiable {
    public var id: UUID { return UUID() }
}

let RaceBoxBLEServiceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
let RaceBoxBLETxCharacteristicUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")

let RaceBoxBLEDeviceInfoServiceUUID = CBUUID(string: "0000180a-0000-1000-8000-00805f9b34fb")
let RaceBoxBLESerialNumberCharacteristicUUID = CBUUID(string: "00002a25-0000-1000-8000-00805f9b34fb")

let FULL_PAYLOAD_LENGTH = 80
