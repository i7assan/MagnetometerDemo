//
//  MagnetometerDemoApp.swift
//  MagnetometerDemo
//
//  Entry point. All of the magnetometer logic lives in MagnetometerManager.swift;
//  the UI is in ContentView.swift.
//
//  Note: Reading the magnetometer does not need an Info.plist usage
//  description or a permission prompt. (NSMotionUsageDescription is only
//  required for motion *activity* and pedometer data.)
//

import SwiftUI

@main
struct MagnetometerDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
