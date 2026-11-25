import Foundation
import Vision
import ImageIO

enum PandaFaces {
  static func detect(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> [[String: Any]] {
    let request = VNDetectFaceLandmarksRequest()
    #if targetEnvironment(simulator)
    // Some simulator runtimes cannot create Vision's default inference context.
    request.usesCPUOnly = true
    #endif
    try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
    return (request.results ?? []).sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }.prefix(8).map { face in
      let b = face.boundingBox
      let box = CGRect(x: b.minX, y: 1-b.maxY, width: b.width, height: b.height)
      let points = face.landmarks?.faceContour?.normalizedPoints.map {
        CGPoint(x: b.minX + CGFloat($0.x)*b.width, y: 1-(b.minY + CGFloat($0.y)*b.height))
      } ?? []
      let cheeks = points.filter { $0.y >= box.minY + box.height * 0.48 && $0.y <= box.minY + box.height * 0.84 }
      let left = cheeks.min(by: { $0.x < $1.x }) ?? CGPoint(x: box.minX+box.width*0.08,y: box.minY+box.height*0.66)
      let right = cheeks.max(by: { $0.x < $1.x }) ?? CGPoint(x: box.maxX-box.width*0.08,y: box.minY+box.height*0.66)
      let lips = face.landmarks?.outerLips?.normalizedPoints.map {
        CGPoint(x:b.minX+CGFloat($0.x)*b.width,y:1-(b.minY+CGFloat($0.y)*b.height))
      } ?? []
      let mouth: [CGFloat] = lips.isEmpty ? [] : [lips.map{$0.x}.reduce(0,+)/CGFloat(lips.count),lips.map{$0.y}.reduce(0,+)/CGFloat(lips.count)]
      return ["outline": points.map{[$0.x,$0.y]}, "mouth":mouth, "box": [box.minX,box.minY,box.width,box.height], "jaw": [left.x,left.y,right.x,right.y]]
    }
  }
}
