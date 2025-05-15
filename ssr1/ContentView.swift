//
//  ContentView.swift
//  ssr1
//
//  Created by Hashashin on 13/5/2025.
//

import SwiftUI

struct ContentView: View {
  @StateObject private var manager = PhotoAudioCaptureManager()

  var body: some View {
    ZStack {
      CameraPreview(session: manager.session).ignoresSafeArea()
      VStack {
        Spacer()
        Button {
          manager.capture()
        } label: {
          Text("Capture 📸 + 🔊")
            .fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white.opacity(0.8))
            .cornerRadius(12)
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 30)
      }
    }
  }
}
