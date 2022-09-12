//
//  ContentView.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/7/22.
//

import SwiftUI




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
        VStack (spacing: 10) {

            Text("RaceBox Test")
                .font(.largeTitle)
                .frame(maxWidth: .infinity, alignment: .center)
            List(bleManager.peripherals) { peripheral in
                Button(action: {
                    bleManager.connectTo(peripheral: peripheral)
                }) {
                    HStack {
                        Text(peripheral.name ?? "Unknown")
                    }
                }
            }.frame(height: 200)
            Spacer()
            
            VStack(spacing: 10) {
                Text("RaceBox Data Feed")
                    .font(.title3)
                VStack() {
                    if (bleManager.currentPacket != nil) {
                        VStack(spacing: 2) {
                            Text("Date: \(convertDateToString(date: bleManager.currentPacket!.date))")
                            Text("Fix Status: \(bleManager.currentPacket!.fixStatus)")
                            Text("Validity Flags: \(bleManager.currentPacket!.validityFlags)")
                            Text("Num of Space Vehicles: \(bleManager.currentPacket!.numberofSVs)")
                            Text("Longitude: \(bleManager.currentPacket!.longitude)")
                            Text("Latitude: \(bleManager.currentPacket!.latitude)")
                        }
                        VStack(spacing: 2) {
                            Text("WGS Altitude: \(bleManager.currentPacket!.wgsAltitude) feet")
                            Text("Speed: \(bleManager.currentPacket!.speed) mph")
                            Text("Heading: \(bleManager.currentPacket!.heading)")
                            Text("Battery Charging: \(String(bleManager.currentPacket!.batteryCharging))")
                            Text("Battery Level: \(bleManager.currentPacket!.batteryLevel)%")
                            Text("GForce X, Y, Z: \(bleManager.currentPacket!.gForceX) \(bleManager.currentPacket!.gForceY) \(bleManager.currentPacket!.gForceZ)")
                            Text("Rotation Rate X, Y, Z: \(bleManager.currentPacket!.rotationRateX) \(bleManager.currentPacket!.rotationRateY) \(bleManager.currentPacket!.rotationRateZ)")
                        }
                    } else {
                        VStack(spacing: 2) {
                            Text("Date: N/A")
                            Text("Fix Status: N/A")
                            Text("Validity Flags: N/A")
                            Text("Num of Space Vehicles: N/A")
                            Text("Longitude: N/A")
                            Text("Latitude: N/A")
                        }
                        VStack(spacing: 2) {
                            Text("WGS Altitude: N/A feet")
                            Text("Speed: N/A mph")
                            Text("Heading: N/A")
                            Text("Battery Charging: N/A")
                            Text("Battery Level: N/A %")
                            Text("GForce X, Y, Z: N/A")
                            Text("Rotation Rate X, Y, Z: N/A")
                        }
                    }
                }
                
                if (self.bleManager.peripheralRSSI != nil) {
                    Text("Connection Strength RSSI: \(bleManager.peripheralRSSI!)")
                } else {
                    Text("Connection Strength RSSI: N/A")
                }
            }.padding()
            

            Spacer()

            HStack {
                VStack(spacing: 10) {
                    Button(action: {
                        bleManager.disconnect()
                    }) {
                        Text("Disconnect Peripheral")
                    }
                }.padding()

                Spacer()
                
                VStack (spacing: 10) {
                    Text("Peripheral Status")
                        .font(.headline)
                    
                    if (bleManager.connectedPeripheral != nil) {
                        Text("Connected to \(bleManager.connectedPeripheral!.name ?? "a peripheral with no name")")
                            .foregroundColor(.green)
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
