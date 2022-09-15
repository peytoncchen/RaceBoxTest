//
//  RaceBoxData.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/13/22.
//

import Foundation

struct RaceBoxData {
    var iTow: UInt32
    var year: UInt16
    var month: Int8
    var day: Int8
    var hour: Int8
    var minute: Int8
    var second: Int8
    var validityFlags: UInt8
    var timeAccuracy: UInt32 // ignoring
    var nanoseconds: Int32 // ignoring
    var fixStatus: Int8
    var fixStatusFlags: UInt8 // ignoring
    var dateTimeFlags: UInt8 // ignoring
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
    var latLongFlags: UInt8 // ignoring
    var batteryStatus: UInt8
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
    var longitude: Double
    var latitude: Double
    var wgsAltitude: Double // converted from mm -> ft
    var speed: Double // converted from mm/s -> mph
    var heading: Double
    var batteryCharging: Bool
    var batteryLevel: UInt
    var gForceX: Double
    var gForceY: Double
    var gForceZ: Double
    var rotationRateX: Double
    var rotationRateY: Double
    var rotationRateZ: Double
}
