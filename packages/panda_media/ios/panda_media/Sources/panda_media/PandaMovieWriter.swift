import Foundation
import AVFoundation
import CoreImage

class PandaMovieWriter {
  let path: String
  let writer: AVAssetWriter
  let input: AVAssetWriterInput
  let adaptor: AVAssetWriterInputPixelBufferAdaptor
  let context = CIContext(options: [.cacheIntermediates: false])
  init(path: String, width: Int, height: Int) throws {
    self.path = path
    writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
    // The Flutter shader outputs sRGB. Tell AVFoundation about the source
    // transfer function and encode a tagged SDR video for Photos and playback.
    input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ])
    input.expectsMediaDataInRealTime = false
    adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    guard writer.canAdd(input) else { throw PandaMediaError.writerFailure }; writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? PandaMediaError.writerFailure }; writer.startSession(atSourceTime: .zero)
  }
  func appendPixels(_ data: Data,width: Int,height: Int,bgra: Bool,timeUs: Int64) throws {
    guard let pool = adaptor.pixelBufferPool else {throw PandaMediaError.writerFailure}
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess,let pixel = buffer else {throw PandaMediaError.writerFailure}
    CVPixelBufferLockBaseAddress(pixel,[])
    let w = min(width,CVPixelBufferGetWidth(pixel)), h = min(height,CVPixelBufferGetHeight(pixel))
    let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
    guard data.count >= width*height*4,let address = CVPixelBufferGetBaseAddress(pixel) else {CVPixelBufferUnlockBaseAddress(pixel,[]);throw PandaMediaError.invalidImage}
    data.withUnsafeBytes { raw in
      let src = raw.bindMemory(to:UInt8.self).baseAddress!
      let dst = address.assumingMemoryBound(to:UInt8.self)
      for y in 0..<h {
        if bgra {memcpy(dst+y*rowBytes,src+y*width*4,w*4)}
        else {for x in 0..<w {let i = y*width*4+x*4, o = y*rowBytes+x*4;dst[o] = src[i+2];dst[o+1] = src[i+1];dst[o+2] = src[i];dst[o+3] = src[i+3]}}
      }
    }
    CVPixelBufferUnlockBaseAddress(pixel,[])
    CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
    CVBufferSetAttachment(pixel, kCVImageBufferCGColorSpaceKey, PandaPixels.sRGB, .shouldPropagate)
    let deadline = Date().addingTimeInterval(10)
    while !input.isReadyForMoreMediaData {if writer.status == .failed || Date() > deadline {throw writer.error ?? PandaMediaError.writerFailure};Thread.sleep(forTimeInterval:0.002)}
    guard adaptor.append(pixel,withPresentationTime:CMTime(value:timeUs,timescale:1_000_000)) else {throw writer.error ?? PandaMediaError.writerFailure}
  }
  func append(_ data: Data, timeUs: Int64) throws {
    guard let image = CIImage(data: data), let pool = adaptor.pixelBufferPool else { throw PandaMediaError.invalidImage }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixel = buffer else { throw PandaMediaError.writerFailure }
    context.render(image, to: pixel)
    let deadline = Date().addingTimeInterval(10)
    while !input.isReadyForMoreMediaData {
      if writer.status == .failed || Date() > deadline { throw writer.error ?? PandaMediaError.writerFailure }
      Thread.sleep(forTimeInterval: 0.002)
    }
    guard adaptor.append(pixel, withPresentationTime: CMTime(value: timeUs, timescale: 1_000_000)) else { throw writer.error ?? PandaMediaError.writerFailure }
  }
  func finish(_ done: @escaping (Error?) -> Void) {
    input.markAsFinished(); writer.finishWriting { done(self.writer.status == .completed ? nil : self.writer.error ?? PandaMediaError.writerFailure) }
  }
  func abort() { writer.cancelWriting(); try? FileManager.default.removeItem(atPath: path) }
}
