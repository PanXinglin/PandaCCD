import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Generate a paired JPEG/MOV, including timed still-image metadata. Photos
/// insertion is handled by the application's existing photo_manager plugin.
enum PandaLivePair {
  static func create(imagePath: String, videoPath: String, keyUs: Int64,
    completion: @escaping ([String: String]?, Error?) -> Void) throws {
    let id = UUID().uuidString
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("panda-pair-"+id)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let photoURL = root.appendingPathComponent("photo.jpg"), movieURL = root.appendingPathComponent("paired.mov")
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL,nil),
      let dest = CGImageDestinationCreateWithURL(photoURL as CFURL,UTType.jpeg.identifier as CFString,1,nil) else { throw PandaMediaError.invalidImage }
    var properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String: Any] ?? [:]
    properties[kCGImagePropertyMakerAppleDictionary as String] = ["17": id]
    properties[kCGImageDestinationLossyCompressionQuality as String] = 0.95
    CGImageDestinationAddImageFromSource(dest,source,0,properties as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw PandaMediaError.invalidImage }
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    guard let track = asset.tracks(withMediaType: .video).first else { throw PandaMediaError.invalidVideo }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track,outputSettings: nil)
    reader.add(output)
    let writer = try AVAssetWriter(outputURL: movieURL,fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video,outputSettings: nil,sourceFormatHint: track.formatDescriptions.first as! CMFormatDescription?)
    input.transform = track.preferredTransform; writer.add(input)
    var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
    if let audioTrack = asset.tracks(withMediaType: .audio).first {
      let audioOutput = AVAssetReaderTrackOutput(track: audioTrack,outputSettings: nil)
      let audioInput = AVAssetWriterInput(mediaType: .audio,outputSettings: nil,sourceFormatHint: audioTrack.formatDescriptions.first as! CMFormatDescription?)
      reader.add(audioOutput); writer.add(audioInput); audioPair = (audioOutput,audioInput)
    }
    let identifier = AVMutableMetadataItem()
    identifier.identifier = .quickTimeMetadataContentIdentifier; identifier.value = id as NSString
    identifier.dataType = kCMMetadataBaseDataType_UTF8 as String; writer.metadata = [identifier]
    var format: CMFormatDescription?
    let spec: [String: Any] = [kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"]
    let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,metadataType: kCMMetadataFormatType_Boxed,
      metadataSpecifications: [spec] as CFArray,formatDescriptionOut: &format)
    guard status == noErr, let metadataFormat = format else { throw PandaMediaError.writerFailure }
    let metadata = AVAssetWriterInput(mediaType: .metadata,outputSettings: nil,sourceFormatHint: metadataFormat)
    writer.add(metadata)
    let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)
    guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? PandaMediaError.writerFailure }
    writer.startSession(atSourceTime: .zero)
    let still = AVMutableMetadataItem()
    still.key = "com.apple.quicktime.still-image-time" as NSString; still.keySpace = .quickTimeMetadata
    still.value = NSNumber(value: Int8(0)); still.dataType = "com.apple.metadata.datatype.int8"
    let key = min(max(0,keyUs),max(0,Int64(asset.duration.seconds * 1_000_000)-50_000))
    guard adaptor.append(AVTimedMetadataGroup(items: [still],timeRange: CMTimeRange(start: CMTime(value: key,timescale: 1_000_000),duration: CMTime(value: 1,timescale: 24)))) else { throw writer.error ?? PandaMediaError.writerFailure }
    metadata.markAsFinished()
    let group = DispatchGroup()
    let lock = NSLock()
    var failure: Error?
    func transfer(_ output: AVAssetReaderTrackOutput,_ input: AVAssetWriterInput,_ label: String) {
      group.enter()
      input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
        while input.isReadyForMoreMediaData {
          if let sample = output.copyNextSampleBuffer() {
            if !input.append(sample) {
              lock.lock(); failure = writer.error ?? PandaMediaError.writerFailure; lock.unlock()
              input.markAsFinished(); group.leave(); return
            }
          } else { input.markAsFinished(); group.leave(); return }
        }
      }
    }
    transfer(output,input,"panda.pair.video."+id)
    if let audio = audioPair { transfer(audio.0,audio.1,"panda.pair.audio."+id) }
    group.notify(queue: DispatchQueue(label: "panda.pair.finish."+id)) {
      if failure != nil || reader.status == .failed {
        writer.cancelWriting(); try? FileManager.default.removeItem(at: root)
        completion(nil,failure ?? reader.error ?? PandaMediaError.writerFailure); return
      }
      writer.finishWriting {
        if writer.status == .completed { completion(["imagePath": photoURL.path,"videoPath": movieURL.path],nil) }
        else { try? FileManager.default.removeItem(at: root); completion(nil,writer.error ?? PandaMediaError.writerFailure) }
      }
    }
  }
}
