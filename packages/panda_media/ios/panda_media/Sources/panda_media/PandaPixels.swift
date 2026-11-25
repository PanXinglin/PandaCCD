import Foundation
import ImageIO
import CoreGraphics
import CoreImage

enum PandaPixels {
  static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
  private static let context = CIContext(options: [.cacheIntermediates: false])
  // Camera buffers are portrait, with the front camera mirrored. Normalize
  // before Vision so its geometry is in the same unmirrored window as Dart.
  static func upright(_ image: CGImage, rotation: Int, mirrored: Bool) throws -> CGImage {
    var input = CIImage(cgImage: image)
    if mirrored { input = input.oriented(.upMirrored) }
    let orientation: CGImagePropertyOrientation = rotation == 90 ? .right : rotation == 180 ? .down : rotation == 270 ? .left : .up
    input = input.oriented(orientation)
    guard let result = context.createCGImage(input, from: input.extent) else { throw PandaMediaError.invalidImage }
    return result
  }

  static func raw(_ image: CGImage) throws -> Data {
    var data = Data(count: image.width*image.height*4)
    let ok = data.withUnsafeMutableBytes { raw -> Bool in
      guard let c = CGContext(data: raw.baseAddress,width: image.width,height: image.height,bitsPerComponent: 8,bytesPerRow: image.width*4,
        space: sRGB,bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue) else {return false}
      c.draw(image,in: CGRect(x:0,y:0,width:image.width,height:image.height));return true
    }
    guard ok else {throw PandaMediaError.invalidImage};return data
  }
  static func image(_ data: Data,width: Int,height: Int,bgra: Bool) throws -> CGImage {
    let info = bgra ? CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue : CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
    guard let provider = CGDataProvider(data:data as CFData),let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:sRGB,bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {throw PandaMediaError.invalidImage}
    return image
  }
}
