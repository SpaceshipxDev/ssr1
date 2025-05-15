//
//  LivePhotoCreator.swift
//  ssr1
//
//  Created by Hashashin on 13/5/2025.
//
import UIKit
import AVFoundation

/// Utility: combine a still UIImage + an audio file into a .mov suitable as Live‑Photo video
struct LivePhotoCreator {
  /// Returns `URL` to the generated .mov (or `nil` on failure)
  static func makeVideo(from image: UIImage,
                        audioURL: URL,
                        duration sec: Double = 3.0) async -> URL? {
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("livephoto_\(UUID()).mov")
    do { if FileManager.default.fileExists(atPath: temp.path) {
      try FileManager.default.removeItem(at: temp) } } catch {}

    guard let imgCG = image.cgImage else { return nil }
    let size = CGSize(width: imgCG.width, height: imgCG.height)

    // ---------- AssetWriter setup ----------
    guard let writer = try? AVAssetWriter(outputURL: temp,
                                          fileType: .mov) else { return nil }

    // Video input (H.264)
    let vidSettings: [String:Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                     AVVideoWidthKey : size.width,
                                     AVVideoHeightKey: size.height]
    let vidInput = AVAssetWriterInput(mediaType: .video,
                                      outputSettings: vidSettings)
    vidInput.expectsMediaDataInRealTime = false
    let adap = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vidInput,
                                                   sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
      kCVPixelBufferWidthKey         as String: size.width,
      kCVPixelBufferHeightKey        as String: size.height
    ])
    writer.add(vidInput)

    // Audio input (AAC) – we’ll copy samples from existing file
    let audSettings: [String:Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44_100,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitRateKey: 192_000
]
    let audInput = AVAssetWriterInput(mediaType: .audio,
                                      outputSettings: audSettings)
    audInput.expectsMediaDataInRealTime = false
    writer.add(audInput)

    guard writer.startWriting() else { return nil }
    writer.startSession(atSourceTime: .zero)

    // ---------- 1) push video frames (still image repeated) ----------
    let fps: Double = 30
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
    var frameCount: Int64 = 0
    let totalFrames = Int64(sec * fps)

    let queue = DispatchQueue(label: "videoQueue")
    queue.sync {
      while frameCount < totalFrames {
        if vidInput.isReadyForMoreMediaData,
           let buf = pixelBuffer(from: image, size: size) {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
          adap.append(buf, withPresentationTime: time)
          frameCount += 1
        }
      }
      vidInput.markAsFinished()
    }

    // ---------- 2) copy audio samples ----------
    let audAsset  = AVURLAsset(url: audioURL)
    guard let audTrack = audAsset.tracks(withMediaType: .audio).first,
          let reader   = try? AVAssetReader(asset: audAsset) else { return nil }
    let readerOut = AVAssetReaderTrackOutput(track: audTrack, outputSettings: nil)
    reader.add(readerOut)
    reader.startReading()

    while let samp = readerOut.copyNextSampleBuffer() {
      if audInput.isReadyForMoreMediaData { audInput.append(samp) }
    }
    audInput.markAsFinished()

    await withCheckedContinuation { cont in
      writer.finishWriting { cont.resume(returning: ()) }
    }

    return writer.status == .completed ? temp : nil
  }

  // Helper: UIImage -> CVPixelBuffer
  private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
    var pxbuf: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    let res = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                  kCVPixelFormatType_32ARGB, attrs, &pxbuf)
    guard res == kCVReturnSuccess, let buf = pxbuf else { return nil }

    CVPixelBufferLockBaseAddress(buf, []);
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                             width: Int(size.width), height: Int(size.height),
                             bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    if let cg = image.cgImage { context?.draw(cg, in: CGRect(origin: .zero, size: size)) }
    CVPixelBufferUnlockBaseAddress(buf, [])
    return buf
  }
}
