//
//  ContentView.swift
//  disk_hog
//
//

import SwiftUI

struct ContentView: View {
    var commandState: ScanWindowCommandState = .shared
    var access: FullDiskAccessSetupModel
    var body: some View {
        SourceWindowView(commandState: commandState, access: access)
    }
}

#Preview {
    ContentView(access: FullDiskAccessSetupModel(checkAccess: { .inconclusive }, openSettings: { false }, terminate: {}))
}
