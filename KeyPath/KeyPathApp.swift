//
//  KeyPathApp.swift
//  KeyPath
//
//  Created by Pallav Agarwal on 6/9/25.
//

import SwiftUI

@main
struct KeyPathApp: App {
    var body: some Scene {
        WindowGroup {
            KeyPathContentView()
        }
        .windowStyle(.hiddenTitleBar)

        // Menu bar app - this creates the status bar item
        MenuBarExtra("KeyPath", systemImage: "keyboard") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
