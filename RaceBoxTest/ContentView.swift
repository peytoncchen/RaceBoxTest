//
//  ContentView.swift
//  RaceBoxTest
//
//  Created by Peyton Chen on 9/7/22.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var bleManager = BLEManager()

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
                if (self.bleManager.currentPacket != nil) {
                    Text(String(describing: bleManager.currentPacket!))
                }
                
                if (self.bleManager.peripheralRSSI != nil) {
                    Text("Connection Strength RSSI: \(bleManager.peripheralRSSI!)")
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
