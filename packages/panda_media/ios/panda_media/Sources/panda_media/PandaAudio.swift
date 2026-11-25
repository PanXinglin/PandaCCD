import Foundation
import AVFoundation

/// Lossless audio-track copy, including offsets across pre-recording segments.
enum PandaAudio {
  static func merge(path: String, sources: [[String: Any]]) throws -> Bool {
    let composition = AVMutableComposition()
    let video = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let sourceVideo = video.tracks(withMediaType: .video).first,
      let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
      let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw PandaMediaError.invalidVideo }
    try v.insertTimeRange(CMTimeRange(start: .zero,duration: video.duration), of: sourceVideo, at: .zero)
    v.preferredTransform = sourceVideo.preferredTransform
    var hasAudio = false
    for source in sources {
      let asset = AVURLAsset(url: URL(fileURLWithPath: source["path"] as! String))
      guard let audio = asset.tracks(withMediaType: .audio).first else { continue }
      let from = CMTime(value: (source["fromUs"] as! NSNumber).int64Value,timescale: 1_000_000)
      let to = CMTimeMinimum(CMTime(value: (source["toUs"] as! NSNumber).int64Value,timescale: 1_000_000),asset.duration)
      let offset = CMTime(value: (source["offsetUs"] as! NSNumber).int64Value,timescale: 1_000_000)
      if to > from { try a.insertTimeRange(CMTimeRange(start: from,end: to),of: audio,at: offset); hasAudio = true }
    }
    if !hasAudio { return false }
    let url = URL(fileURLWithPath: path+".audio.mp4")
    try? FileManager.default.removeItem(at: url)
    guard let export = AVAssetExportSession(asset: composition,presetName: AVAssetExportPresetPassthrough) else { throw PandaMediaError.writerFailure }
    export.outputURL = url; export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    guard done.wait(timeout: .now()+60) == .success, export.status == .completed else { export.cancelExport();throw export.error ?? PandaMediaError.writerFailure }
    _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path),withItemAt: url)
    return true
  }
}
