import Foundation
import Photos
import CryptoKit

/// Insert the already rendered/paired files once. Returning the placeholder ID
/// works with add-only permission; fetching the asset would require read access.
enum PandaPhotos {
  enum PreflightError: Error {
    case invalidSource
    case permissionDenied
  }

  static func findExport(_ args: [String: Any]) async -> String? {
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
      let title = args["title"] as? String,
      let imageHash = args["imageHash"] as? String,
      let timestamp = args["dateMs"] as? NSNumber else { return nil }
    let videoHash = args["videoHash"] as? String
    let date = Date(timeIntervalSince1970: timestamp.doubleValue / 1000)
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
      date.addingTimeInterval(-1) as NSDate, date.addingTimeInterval(1) as NSDate)
    let assets = PHAsset.fetchAssets(with: .image, options: options)
    var match: String?
    for index in 0..<assets.count {
      let asset = assets.object(at: index)
      let resources = PHAssetResource.assetResources(for: asset)
      guard let image = resources.first(where: {
        $0.type == .photo && $0.originalFilename == title
      }) else { continue }
      guard await digest(image) == imageHash else { continue }
      if let videoHash = videoHash {
        guard let video = resources.first(where: { $0.type == .pairedVideo }),
          await digest(video) == videoHash else { continue }
      }
      if match != nil { return nil }
      match = asset.localIdentifier
    }
    return PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ? match : nil
  }

  private static func digest(_ resource: PHAssetResource) async -> String? {
    await withCheckedContinuation { continuation in
      var hash = SHA256()
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = false
      PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
        hash.update(data: data)
      } completionHandler: { error in
        let digest = error == nil ? hash.finalize().map { String(format: "%02x", $0) }.joined() : nil
        continuation.resume(returning: digest)
      }
    }
  }

  static func save(_ args: [String: Any], completion: @escaping (String?, Error?) -> Void) {
    guard let path = args["imagePath"] as? String,
      let title = args["title"] as? String,
      FileManager.default.fileExists(atPath: path) else {
      completion(nil, PreflightError.invalidSource); return
    }
    let video = args["videoPath"] as? String
    if let video = video, !FileManager.default.fileExists(atPath: video) {
      completion(nil, PreflightError.invalidSource); return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized else {
        completion(nil, PreflightError.permissionDenied); return
      }
      var identifier: String?
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        if let timestamp = args["dateMs"] as? NSNumber {
          request.creationDate = Date(timeIntervalSince1970: timestamp.doubleValue / 1000)
        }
        let imageOptions = PHAssetResourceCreationOptions()
        imageOptions.originalFilename = title
        request.addResource(with: .photo, fileURL: URL(fileURLWithPath: path), options: imageOptions)
        if let video = video {
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = (title as NSString).deletingPathExtension + ".mov"
          request.addResource(with: .pairedVideo, fileURL: URL(fileURLWithPath: video), options: options)
        }
        identifier = request.placeholderForCreatedAsset?.localIdentifier
      } completionHandler: { success, error in
        completion(success ? identifier : nil, success && identifier != nil ? nil :
          (error ?? PandaMediaError.writerFailure))
      }
    }
  }
}
