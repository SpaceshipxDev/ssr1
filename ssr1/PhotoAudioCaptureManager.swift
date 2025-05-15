//
//  PhotoAudioCaptureManager.swift
//  ssr1
//
//  Created by Hashashin on 13/5/2025.
//

import SwiftUI
import AVFoundation
import Photos
import ReplayKit

@MainActor
final class PhotoAudioCaptureManager: NSObject, ObservableObject {

  @Published var session = AVCaptureSession()

  // MARK: – private state
  private let photoOut = AVCapturePhotoOutput()
  private var audioWriter : AVAssetWriter?
  private var audioInput  : AVAssetWriterInput?
  private var audioURL    : URL?
  private var isAudioRecording = false   // <- NEW

  static let captureSeconds: Double = 3   // Live-Photo UI only plays ~3 s

  override init() {
    super.init()
    Task { await requestAndConfigure() }
  }

  // 1. Ask permission → set up → start session → build preview layer later
  private func requestAndConfigure() async {
    guard await AVCaptureDevice.requestAccess(for: .video) else { return }

    session.beginConfiguration()
    session.sessionPreset = .photo

    // camera input
    if let cam = AVCaptureDevice.default(.builtInWideAngleCamera,
                                         for: .video,
                                         position: .back),
       let input = try? AVCaptureDeviceInput(device: cam),
       session.canAddInput(input) {
      session.addInput(input)
    }

    // photo output
    if session.canAddOutput(photoOut) { session.addOutput(photoOut) }
    session.commitConfiguration()

    session.startRunning()  // safe – we own the session

    // Now that it's running, publish a dummy layer to kick UI refresh
    DispatchQueue.main.async {
      self.objectWillChange.send()
    }
  }

  // MARK: – public entry point from the button
  func capture() {
    startAudio()
    photoOut.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
  }

  // MARK: – start internal-audio capture safely
  private func startAudio() {
    audioURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("cap_\(UUID()).m4a")
    try? FileManager.default.removeItem(at: audioURL!)

    // AssetWriter
    guard let writer = try? AVAssetWriter(outputURL: audioURL!, fileType: .m4a) else {
      print("⚠️ cannot create AVAssetWriter"); return
    }
    let asettings: [String:Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey: 192_000
    ]
    let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: asettings)
    aInput.expectsMediaDataInRealTime = true
    writer.add(aInput)

    audioWriter = writer
    audioInput  = aInput
    isAudioRecording = false                 // reset

    let rp = RPScreenRecorder.shared()
    rp.isMicrophoneEnabled = false

    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    rp.startCapture(handler: { [weak self] buf, type, err in
      guard let self,
            err == nil,
            type == .audioApp,
            self.audioInput?.isReadyForMoreMediaData == true
      else { return }

      self.audioInput?.append(buf)
      self.isAudioRecording = true           // now we know capture succeeded

    }) { err in
      if let e = err {
        print("⚠️ ReplayKit startCapture failed:", e.localizedDescription)
      }
    }

    // schedule stop
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureSeconds) { [weak self] in
      guard let self else { return }
      if self.isAudioRecording {
        rp.stopCapture { _ in }              // ignore stop error
      }
      if self.audioWriter?.status == .writing {
        self.audioInput?.markAsFinished()
        self.audioWriter?.finishWriting {
          print("🔊 audio clip finished at:", self.audioURL!)
        }
      }
    }
  }
}

// MARK: – photo delegate
extension PhotoAudioCaptureManager: AVCapturePhotoCaptureDelegate {

  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishProcessingPhoto photo: AVCapturePhoto,
                   error: Error?) {

    guard let data = photo.fileDataRepresentation(),
          let img  = UIImage(data: data),
          let audioURL = audioURL
    else { return }

    Task {
      guard let movURL = await LivePhotoCreator
        .makeVideo(from: img,
                   audioURL: audioURL,
                   duration: Self.captureSeconds)
      else { print("⚠️ failed to build Live-Photo video"); return }

      // Save as Live Photo
      PHPhotoLibrary.shared().performChanges {
        let req = PHAssetCreationRequest.forAsset()
        req.addResource(with: .photo, data: data, options: nil)

        let opts = PHAssetResourceCreationOptions()
        opts.shouldMoveFile = true           // move, don’t copy temp .mov
        req.addResource(with: .pairedVideo, fileURL: movURL, options: opts)

      } completionHandler: { ok, err in
        print(ok ? "✅ Live Photo saved" : "❌ save failed",
              err?.localizedDescription ?? "")
      }
    }
  }
}

