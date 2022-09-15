//
//  ContentView.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/7/22.
//

import SwiftUI

struct ListRows: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Text(value)
        }
    }
}

struct ContentView: View {
    
    @ObservedObject var bleManager = RaceBoxManager()
    
    private func convertDateToString(date: Date?) -> String {
        if date == nil {
            return "N/A"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YY, MMM d, HH:mm:ss"
        return dateFormatter.string(from: date!)
    }
    

    var body: some View {
        VStack (spacing: 5) {

            Text("RaceBox Test")
                .font(.largeTitle)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Discoverable RaceBox Minis")
                .font(.title3)
            if (bleManager.connectedPeripheral == nil) {
                List(bleManager.peripherals) { peripheral in
                    Button(action: {
                        bleManager.connectTo(peripheral: peripheral)
                    }) {
                        HStack {
                            Text(peripheral.name ?? "Unknown")
                        }
                    }
                }.frame(height: 135)
            } else {
                Text("Disconnect to connect to another RaceBox")
                    .frame(height: 150)
            }
            
            
            
            VStack(spacing: 5) {
                Text("RaceBox Data Feed")
                    .font(.title3)
                VStack() {
                    if (bleManager.currentPacket != nil) {
                        List {
                            VStack {
                                ListRows(title: "Date", value: "\(convertDateToString(date: bleManager.currentPacket!.date))")
                                ListRows(title: "Fix Status", value: "\(bleManager.currentPacket!.fixStatus)")
                                ListRows(title: "Validity Flags", value: "\(bleManager.currentPacket!.validityFlags.trimmingCharacters(in: .whitespacesAndNewlines))")
                                ListRows(title: "Num of Space Vehicles", value: "\(bleManager.currentPacket!.numberofSVs)")
                            }
                            VStack {
                                ListRows(title: "Longitude", value: "\(String(format: "%.5f", bleManager.currentPacket!.longitude))")
                                ListRows(title: "Latitude", value: "\(String(format: "%.5f",bleManager.currentPacket!.latitude))")
                                ListRows(title: "Speed", value: "\(String(format: "%.5f", bleManager.currentPacket!.speed)) mph")
                                ListRows(title: "Heading", value: "\(String(format: "%.5f", bleManager.currentPacket!.heading))")
                                ListRows(title: "WGS Altitude", value: "\(String(format: "%.5f", bleManager.currentPacket!.wgsAltitude)) feet")
                            }
                            VStack {
                                ListRows(title: "Battery Charging", value: "\(String(bleManager.currentPacket!.batteryCharging))")
                                ListRows(title: "Battery Level", value: "\(bleManager.currentPacket!.batteryLevel)%")
                            }
                            VStack {
                                
                                ListRows(title: "GForce (XYZ)", value: "\(String(format: "%.3f", bleManager.currentPacket!.gForceX)) \(String(format: "%.3f", bleManager.currentPacket!.gForceY)) \(String(format: "%.3f",bleManager.currentPacket!.gForceZ))")
                                ListRows(title: "Rotation Rate (XYZ)", value: "\(String(format: "%.3f", bleManager.currentPacket!.rotationRateX)) \(String(format: "%.3f", bleManager.currentPacket!.rotationRateY)) \(String(format: "%.3f", bleManager.currentPacket!.rotationRateZ))")
                            }
                            
                        }
                        .listStyle(.insetGrouped)
                    } else {
                        List {
                            VStack {
                                ListRows(title: "Date", value: "N/A")
                                ListRows(title: "Fix Status", value: "N/A")
                                ListRows(title: "Validity Flags", value: "N/A")
                                ListRows(title: "Num of Space Vehicles", value: "N/A")
                            }
                            VStack {
                                ListRows(title: "Longitude", value: "N/A")
                                ListRows(title: "Latitude", value: "N/A")
                                ListRows(title: "Speed", value: "N/A")
                                ListRows(title: "Heading", value: "N/A")
                                ListRows(title: "WGS Altitude", value: "N/A")
                            }
                            VStack {
                                ListRows(title: "Battery Charging", value: "N/A")
                                ListRows(title: "Battery Level", value: "N/A")
                            }
                            VStack {
                                
                                ListRows(title: "GForce X, Y, Z", value: "N/A")
                                ListRows(title: "Rotation Rate X, Y, Z", value: "N/A")
                            }
                            
                        }
                        .listStyle(.insetGrouped)
                    }
                }.overlay(
                    RoundedRectangle(cornerRadius: 10, style: .circular).stroke(Color(uiColor: .tertiaryLabel), lineWidth: 1)
                )
                
                if (self.bleManager.peripheralRSSI != nil) {
                    Text("Connection Strength RSSI: \(bleManager.peripheralRSSI!)")
                } else {
                    Text("Connection Strength RSSI: N/A")
                }
                if (self.bleManager.peripheralSerialNumber != nil) {
                    Text("Peripheral Serial Number: \(bleManager.peripheralSerialNumber!)")
                } else {
                    Text("Peripheral Serial Number: N/A")
                }
                Text("Hz since connection: \(String(format: "%.5f", bleManager.Hz)) Hz")
            }.padding()

            HStack {
                VStack(spacing: 10) {
                    Button(action: {
                        bleManager.disconnect()
                    }) {
                        Text("Disconnect RaceBox Mini")
                    }.buttonStyle(.bordered)
                }.padding()

                Spacer()
                
                VStack (spacing: 10) {
                    Text("RaceBox Mini Status")
                        .font(.headline)
                    
                    if (bleManager.connectedPeripheral != nil) {
                        Text("Connected to \(bleManager.connectedPeripheral!.name ?? "a peripheral with no name")")
                            .foregroundColor(.green)
                    } else if (bleManager.connecting) {
                        Text("Connecting...")
                            .foregroundColor(.yellow)
                    } else {
                        Text("Not connected to anything")
                            .foregroundColor(.red)
                    }
                    
                }.padding()
                
            }
            Spacer()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
