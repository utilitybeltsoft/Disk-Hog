//
//  ContentView.swift
//  disk_hog
//
//

import SwiftUI

struct ContentView: View {
    var commandState: ScanWindowCommandState = .shared
    var body: some View {
        SourceWindowView(commandState: commandState)
    }
}

#Preview {
    ContentView()
}
