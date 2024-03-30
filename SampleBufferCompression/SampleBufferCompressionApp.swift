//
//  SampleBufferCompressionApp.swift
//  SampleBufferCompression
//
//  Created by Justin Allen on 3/28/24.
//

import SwiftUI

@main
struct SampleBufferCompressionApp: App {
    var audioTester: AudioTest1 = AudioTest1()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    audioTester.startTest()
                }
        }
    }
}
