import Flutter
import UIKit
import AVFoundation
import Vision
import ImageIO
import CoreImage
import UniformTypeIdentifiers

/// System media, camera metadata and Vision coordinates. Image effects stay in Dart/GLSL.
public class PandaMediaPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "panda.media")
  private var readers: [String: AVAssetImageGenerator] = [:]
  private var writers: [String: PandaMovieWriter] = [:]
  // Accessed only on the main queue. Expiration also closes the assertion.
  private var liveFinishes: [String: UIBackgroundTaskIdentifier] = [:]
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "panda_ccd/media", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PandaMediaPlugin(), channel: channel)
  }
  private static func rearZoomConfiguration() -> [String: Any] {
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera],
      mediaType: .video, position: .back).devices
    guard let camera = devices.max(by: { $0.constituentDevices.count < $1.constituentDevices.count })
    else { return [:] }
    let lenses = camera.constituentDevices
    let factors = [1.0] + camera.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
    guard factors.count == lenses.count,
      let main = lenses.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
      factors[main] > 0 else { return [:] }
    let stops = Dictionary(uniqueKeysWithValues: zip(lenses, factors).map { lens, factor in
      (lens.uniqueID, factor / factors[main])
    })
    return ["camera": camera.uniqueID, "mainLevel": factors[main], "factors": stops]
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "rearZoomConfiguration" {
      result(Self.rearZoomConfiguration())
      return
    }
    if call.method == "beginLiveFinish" || call.method == "endLiveFinish" {
      DispatchQueue.main.async {
        if call.method == "beginLiveFinish" {
          let id = UUID().uuidString
          let task = UIApplication.shared.beginBackgroundTask(withName: "Finish Live capture") { [weak self] in
            self?.endLiveFinish(id)
          }
          if task == .invalid { result(nil); return }
          self.liveFinishes[id] = task
          result(id)
        } else {
          if let id = (call.arguments as? [String: Any])?["id"] as? String {
            self.endLiveFinish(id)
          }
          result(nil)
        }
      }
      return
    }
    queue.async {
      let a = call.arguments as? [String: Any] ?? [:]
      do {
        if call.method == "savePhoto" {
          PandaPhotos.save(a) { response, error in
            DispatchQueue.main.async {
              if let error = error {
                let code: String
                switch error as? PandaPhotos.PreflightError {
                case .permissionDenied: code = "PHOTOS_WRITE_DENIED"
                case .invalidSource: code = "PHOTOS_NOT_CREATED"
                case nil: code = "PHOTOS_FAILED"
                }
                result(FlutterError(code: code, message: error.localizedDescription, details: nil))
              }
              else { result(response) }
            }
          }
          return
        }
        if call.method == "findPhotoExport" {
          Task {
            let id = await PandaPhotos.findExport(a)
            DispatchQueue.main.async { result(id) }
          }
          return
        }
        if call.method == "pairLive" {
          try PandaLivePair.create(imagePath: a["imagePath"] as! String, videoPath: a["videoPath"] as! String,
            keyUs: (a["keyUs"] as! NSNumber).int64Value) { response, error in
              DispatchQueue.main.async {
                if let error = error { result(FlutterError(code: "MEDIA_FAILED", message: error.localizedDescription, details: nil)) }
                else { result(response) }
              }
            }
          return
        }
        let value: Any?
        switch call.method {
        case "device": value = ["brand": "apple", "manufacturer": "apple"]
        case "jpeg":
          guard let image = UIImage(data: (a["bytes"] as! FlutterStandardTypedData).data),
            let data = image.jpegData(compressionQuality: 0.95) else { throw PandaMediaError.invalidImage }
          value = FlutterStandardTypedData(bytes: data)
        case "detectPhoto":
          guard let source = CGImageSourceCreateWithData((a["bytes"] as! FlutterStandardTypedData).data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PandaMediaError.invalidImage }
          value = try PandaFaces.detect(image, orientation: .up)
        case "detectPixels":
          let image = try PandaPixels.image((a["bytes"] as! FlutterStandardTypedData).data,width:a["width"] as! Int,height:a["height"] as! Int,bgra:a["bgra"] as? Bool ?? false)
          value = try PandaFaces.detect(image,orientation:.up)
        case "detectFrame":
          let bytes = (a["bytes"] as! FlutterStandardTypedData).data
          let w = a["width"] as! Int, h = a["height"] as! Int, stride = a["stride"] as! Int
          let rotation = a["rotation"] as! Int
          guard let provider = CGDataProvider(data: bytes as CFData), let image = CGImage(width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw PandaMediaError.invalidImage }
          value = try PandaFaces.detect(PandaPixels.upright(image, rotation: rotation, mirrored: a["mirrored"] as? Bool ?? false), orientation: .up)
        case "openReader":
          let asset = AVURLAsset(url: URL(fileURLWithPath: a["path"] as! String))
          let reader = AVAssetImageGenerator(asset: asset)
          reader.appliesPreferredTrackTransform = true
          reader.requestedTimeToleranceBefore = .zero; reader.requestedTimeToleranceAfter = .zero
          reader.maximumSize = CGSize(width: 960, height: 960)
          let id = UUID().uuidString; self.readers[id] = reader
          value = ["id": id, "durationUs": Int64(asset.duration.seconds * 1_000_000)]
        case "readPixels":
          guard let reader = self.readers[a["id"] as! String] else {throw PandaMediaError.closed}
          let edge = (a["maxEdge"] as? Int) ?? 720
          reader.maximumSize = CGSize(width:edge,height:edge)
          reader.requestedTimeToleranceBefore = CMTime(value:1,timescale:30); reader.requestedTimeToleranceAfter = CMTime(value:1,timescale:30)
          let image = try reader.copyCGImage(at:CMTime(value:(a["timeUs"] as! NSNumber).int64Value,timescale:1_000_000),actualTime:nil)
          value = ["bytes":FlutterStandardTypedData(bytes:try PandaPixels.raw(image)),"width":image.width,"height":image.height,"bgra":true]
        case "readFrame":
          guard let reader = self.readers[a["id"] as! String] else { throw PandaMediaError.closed }
          let edge = (a["maxEdge"] as? Int) ?? 720
          reader.maximumSize = CGSize(width: edge, height: edge)
          reader.requestedTimeToleranceBefore = CMTime(value: 1,timescale: 30)
          reader.requestedTimeToleranceAfter = CMTime(value: 1,timescale: 30)
          let image = try reader.copyCGImage(at: CMTime(value: (a["timeUs"] as! NSNumber).int64Value, timescale: 1_000_000), actualTime: nil)
          guard let data = UIImage(cgImage: image).pngData() else { throw PandaMediaError.invalidImage }
          value = FlutterStandardTypedData(bytes: data)
        case "closeReader": self.readers.removeValue(forKey: a["id"] as! String)?.cancelAllCGImageGeneration(); value = nil
        case "openWriter":
          let id = UUID().uuidString
          self.writers[id] = try PandaMovieWriter(path: a["path"] as! String, width: a["width"] as! Int, height: a["height"] as! Int)
          value = id
        case "appendPixels":
          guard let writer = self.writers[a["id"] as! String] else {throw PandaMediaError.closed}
          try writer.appendPixels((a["bytes"] as! FlutterStandardTypedData).data,width:a["width"] as! Int,height:a["height"] as! Int,bgra:a["bgra"] as? Bool ?? false,timeUs:(a["timeUs"] as! NSNumber).int64Value); value = nil
        case "appendFrame":
          guard let writer = self.writers[a["id"] as! String] else { throw PandaMediaError.closed }
          try writer.append((a["bytes"] as! FlutterStandardTypedData).data, timeUs: (a["timeUs"] as! NSNumber).int64Value); value = nil
        case "copyAudio":
          value = ["hasAudio": try PandaAudio.merge(path: a["path"] as! String, sources: a["sources"] as! [[String: Any]])]
        case "finishWriter":
          guard let writer = self.writers.removeValue(forKey: a["id"] as! String) else { throw PandaMediaError.closed }
          writer.finish { error in
            DispatchQueue.main.async {
              if let error = error { result(FlutterError(code: "MEDIA_FAILED", message: error.localizedDescription, details: nil)) }
              else { result(writer.path) }
            }
          }; return
        case "abortWriter": self.writers.removeValue(forKey: a["id"] as! String)?.abort(); value = nil
        default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
        }
        DispatchQueue.main.async { result(value) }
      } catch { DispatchQueue.main.async { result(FlutterError(code: "MEDIA_FAILED", message: error.localizedDescription, details: nil)) } }
    }
  }

  @MainActor private func endLiveFinish(_ id: String) {
    if let task = liveFinishes.removeValue(forKey: id) {
      UIApplication.shared.endBackgroundTask(task)
    }
  }
}

enum PandaMediaError: Error { case invalidImage, closed, writerFailure, invalidVideo }

