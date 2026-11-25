import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let items:[(String,String,String)] = [
  ("01-camera", "把日常，拍出 CCD 质感。", "实时取景，选好风格再按快门。"),
  ("02-styles", "换个机型，换种色彩。", "机型灵感与原创预设，一眼选到喜欢的。"),
  ("03-beauty", "好看的分寸，自己调。", "磨皮、匀肤、提亮、下颌，分别可调。"),
  ("04-editor", "拍完，还能慢慢调。", "风格、细调、构图、水印，各有位置。"),
  ("05-album", "喜欢的照片，好好收着。", "浏览、编辑、批量管理，都在相册里。")
]
let ink=NSColor(srgbRed:0.10,green:0.12,blue:0.15,alpha:1)
let grey=NSColor(srgbRed:0.34,green:0.38,blue:0.43,alpha:1)
func text(_ value:String,_ rect:NSRect,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ color:NSColor = ink) {
  let style=NSMutableParagraphStyle();style.lineBreakMode = .byWordWrapping
  (value as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:style])
}
class Art:NSView {
  var paint:((NSRect)->Void)!
  override var isFlipped:Bool {true}
  override func draw(_ dirtyRect:NSRect){paint(bounds)}
}
func png(_ url:URL,_ width:Int,_ height:Int,_ draw:@escaping(NSRect)->Void) throws {
  let cg=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  cg.translateBy(x:0,y:CGFloat(height));cg.scaleBy(x:1,y:-1)
  NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true)
  draw(NSRect(x:0,y:0,width:width,height:height))
  NSGraphicsContext.restoreGraphicsState()
  let output=CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,1,nil)!
  CGImageDestinationAddImage(output,cg.makeImage()!,nil)
  precondition(CGImageDestinationFinalize(output))
}
_ = NSApplication.shared
for (device,w,h) in [("phone",1290,2796),("ipad",2064,2752)] {
  let folder=root.appendingPathComponent("screenshots/\(device)")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  for (index,item) in items.enumerated(){
    let source=root.appendingPathComponent("screenshots/raw/\(device)-\(item.0).png")
    guard let image=NSImage(contentsOf:source) else {fatalError("Missing screen: \(source.path)")}
    try png(folder.appendingPathComponent("\(item.0).png"),w,h){ bounds in
      NSColor(srgbRed:0.96,green:0.97,blue:0.98,alpha:1).setFill();bounds.fill()
      let left:CGFloat=device == "phone" ? 92 : 130
      text("PandaCCD   /   RETRO CAMERA",NSRect(x:left,y:72,width:1400,height:45),30,.medium,grey)
      NSColor(srgbRed:0.76,green:0.43,blue:0.37,alpha:1).setFill()
      NSBezierPath(ovalIn:NSRect(x:CGFloat(w)-left-13,y:85,width:13,height:13)).fill()
      text(item.1,NSRect(x:left,y:155,width:CGFloat(w)-left*2,height:110),device == "phone" ? 68 : 82,.semibold)
      text(item.2,NSRect(x:left,y:273,width:CGFloat(w)-left*2,height:60),device == "phone" ? 33 : 38,.regular,grey)
      let top:CGFloat=388, bottom:CGFloat=100
      let maxHeight=CGFloat(h)-top-bottom
      let ratio=image.size.width/image.size.height
      let height=min(maxHeight,(CGFloat(w)-left*2)/ratio)
      let width=height*ratio
      let frame=NSRect(x:(CGFloat(w)-width)/2,y:top+(maxHeight-height)/2,width:width,height:height)
      let path=NSBezierPath(roundedRect:frame,xRadius:device == "phone" ? 40 : 30,yRadius:device == "phone" ? 40 : 30)
      NSGraphicsContext.saveGraphicsState()
      let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.13);shadow.shadowBlurRadius=32;shadow.shadowOffset=NSSize(width:0,height:10);shadow.set()
      NSColor.white.setFill();path.fill();NSGraphicsContext.restoreGraphicsState()
      NSGraphicsContext.saveGraphicsState();path.addClip()
      image.draw(in:frame,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
      NSGraphicsContext.restoreGraphicsState()
      NSColor(srgbRed:0.80,green:0.83,blue:0.86,alpha:1).setStroke();path.lineWidth=2;path.stroke()
      let note=item.0 == "03-beauty" ? "AI 生成人像示例 · 经应用实际美颜与滤镜处理" : "AI 示例图 · 经应用实际滤镜处理"
      text(note,NSRect(x:left,y:CGFloat(h)-58,width:CGFloat(w)-left*2,height:35),device == "phone" ? 22 : 27,.regular,grey)
      text(String(format:"%02d",index+1),NSRect(x:CGFloat(w)-left-65,y:CGFloat(h)-58,width:65,height:35),22,.medium,grey)
    }
  }
}
try png(root.appendingPathComponent("images/store-overview.png"),1500,720){ bounds in
  NSColor.white.setFill();bounds.fill()
  for (i,item) in items.enumerated(){
    let image=NSImage(contentsOf:root.appendingPathComponent("screenshots/phone/\(item.0).png"))!
    image.draw(in:NSRect(x:CGFloat(i)*300+12,y:40,width:276,height:598),from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
  }
  text("PandaCCD · App Store 上架素材 · 2026.11.12",NSRect(x:25,y:662,width:1450,height:40),25,.medium,grey)
}
print("Rendered 10 App Store graphics and overview")
