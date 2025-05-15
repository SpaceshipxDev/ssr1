//
//  CameraPreview.swift
//  ssr1
//
//  Created by Hashashin on 13/5/2025.
//

import SwiftUI
import AVFoundation

/// SwiftUI wrapper around an AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.connection?.videoRotationAngle = 0   // portrait (iOS‑17 API)
    view.layer.addSublayer(layer)
    context.coordinator.layer = layer
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.layer?.frame = uiView.bounds
  }

  func makeCoordinator() -> Coordinator { Coordinator() }
  class Coordinator { var layer: AVCaptureVideoPreviewLayer? }
}
