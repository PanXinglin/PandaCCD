import Foundation
import AVFoundation
import ImageIO

enum PandaMediaError: Error { case invalidImage, closed, writerFailure, invalidVideo }

// This exercises the real Apple media helpers on macOS. It does NOT prove
// Flutter/iOS linkage, camera hardware, Photos permission or iPhone behavior.
@main struct IOSCoreCheck {
  static func main() throws {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let w = 64, h = 96
    let colors: [[UInt8]] = [[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,255,0,255]]
    var data = Data()
    for y in 0..<h { for x in 0..<w { data.append(contentsOf: colors[(y < h/2 ? 0 : 2)+(x < w/2 ? 0 : 1)]) } }
    let image = try PandaPixels.image(data, width:w,height:h,bgra:false)
    let maps = [[1,0,3,2],[3,1,2,0],[2,3,0,1],[0,2,1,3]]
    for turn in 0..<4 {
      let normalized = try PandaPixels.upright(image,rotation:turn*90,mirrored:true)
      let raw = [UInt8](try PandaPixels.raw(normalized))
      for y in 0..<2 { for x in 0..<2 {
        let index = ((normalized.height*(y*2+1)/4)*normalized.width+normalized.width*(x*2+1)/4)*4
        let expected = colors[maps[turn][y*2+x]]
        precondition(raw[index] == expected[2] && raw[index+1] == expected[1] && raw[index+2] == expected[0], "Orientation/mirror mismatch")
      } }
    }
    print("APPLE_PIXEL_FOUR_DIRECTIONS_PASS")
    let movie = folder.appendingPathComponent("movie.mp4")
    try? FileManager.default.removeItem(at:movie)
    let writer = try PandaMovieWriter(path:movie.path,width:w,height:h)
    for i in 0..<36 { try writer.appendPixels(data,width:w,height:h,bgra:false,timeUs:Int64(i)*1_000_000/24) }
    let written = DispatchSemaphore(value:0)
    var writerError: Error?
    writer.finish { writerError=$0; written.signal() }
    precondition(written.wait(timeout:.now()+30) == .success)
    if let error=writerError { throw error }
    let audioSource = folder.appendingPathComponent("audio.mp4")
    if FileManager.default.fileExists(atPath:audioSource.path) {
      let audio = try PandaAudio.merge(path:movie.path,sources:[["path":audioSource.path,"fromUs":0,"toUs":1_500_000,"offsetUs":0]])
      precondition(audio)
    }
    let still = folder.appendingPathComponent("still.png")
    let destination = CGImageDestinationCreateWithURL(still as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(destination,image,nil)
    precondition(CGImageDestinationFinalize(destination))
    let paired = DispatchSemaphore(value:0)
    var response:[String:String]?, pairError:Error?
    try PandaLivePair.create(imagePath:still.path,videoPath:movie.path,keyUs:750000) { response=$0;pairError=$1;paired.signal() }
    precondition(paired.wait(timeout:.now()+30) == .success)
    if let error=pairError { throw error }
    let output=response!
    let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:output["imagePath"]!) as CFURL,nil)!
    let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil)! as NSDictionary
    let id=(props[kCGImagePropertyMakerAppleDictionary] as! NSDictionary)["17"] as! String
    let asset=AVURLAsset(url:URL(fileURLWithPath:output["videoPath"]!))
    precondition(asset.metadata.first{$0.identifier == .quickTimeMetadataContentIdentifier}?.stringValue == id)
    precondition(asset.tracks(withMediaType:.metadata).count == 1)
    if FileManager.default.fileExists(atPath:audioSource.path) { precondition(asset.tracks(withMediaType:.audio).count == 1) }
    let reader=try AVAssetReader(asset:asset)
    let out=AVAssetReaderTrackOutput(track:asset.tracks(withMediaType:.metadata)[0],outputSettings:nil)
    reader.add(out)
    let metadataReader = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: out)
    precondition(reader.startReading())
    var keyTime: Double?
    while let group = metadataReader.nextTimedMetadataGroup() {
      for item in group.items where item.identifier?.rawValue == "mdta/com.apple.quicktime.still-image-time" {
        keyTime = group.timeRange.start.seconds
      }
    }
    print("APPLE_STILL_TIME", keyTime as Any)
    precondition(keyTime != nil && abs(keyTime! - 0.75) < 0.002)
    reader.cancelReading()
    print("APPLE_LIVE_PAIR_ID_AUDIO_KEYFRAME_PASS")
    try FileManager.default.removeItem(at:URL(fileURLWithPath:output["imagePath"]!).deletingLastPathComponent())
    let portrait=folder.appendingPathComponent("portrait.jpg")
    if let input=CGImageSourceCreateWithURL(portrait as CFURL,nil),let faceImage=CGImageSourceCreateImageAtIndex(input,0,nil) {
      let faces=try PandaFaces.detect(faceImage,orientation:.up)
      precondition(!faces.isEmpty && !(faces[0]["outline"] as! [[CGFloat]]).isEmpty)
      print("APPLE_VISION_LANDMARKS_PASS")
    }
  }
}
