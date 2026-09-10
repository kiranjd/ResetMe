import AppKit

// Approved leaf silhouette, kept as editable cubic paths for every export.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets/Brand")
let web = root.appendingPathComponent("website/assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let upper = "M926 197 C850 318 598 333 540 527 C524 573 528 617 535 638 C577 661 617 690 651 711 C667 595 831 547 867 386 C852 550 685 623 693 719 C692 765 755 795 798 879 C810 752 894 705 941 571 C998 411 959 280 926 197 Z"
let lower = "M329 510 C277 595 267 749 322 850 C406 1014 620 1097 812 1042 C825 871 699 770 538 676 C443 622 374 585 329 510 Z"
func svg(_ first: String, _ second: String, background: String? = nil, lockup: Bool = false) -> String {
    let bg = background.map { "<rect width=\"\(lockup ? 2700 : 1254)\" height=\"1254\" rx=\"220\" fill=\"\($0)\"/>" } ?? ""
    let text = lockup ? "<text x=\"1130\" y=\"770\" font-family=\"-apple-system,BlinkMacSystemFont,Helvetica,sans-serif\" font-size=\"400\" font-weight=\"600\" letter-spacing=\"-18\" fill=\"\(second)\">ResetMe</text>" : ""
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(lockup ? 2700 : 1254) 1254\">\(bg)<path fill=\"\(first)\" d=\"\(upper)\"/><path fill=\"\(second)\" d=\"\(lower)\"/>\(text)</svg>"
}
func color(_ hex: Int) -> NSColor { NSColor(srgbRed: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, alpha: 1) }
// The raster/PDF renderer consumes these same SVG path coordinates.
func path(_ data: String) -> NSBezierPath {
    let p = NSBezierPath()
    // Split command letters from coordinates, including tokens such as M926.
    let expanded = data.replacingOccurrences(of: "([MCZ])", with: " $1 ", options: .regularExpression).split(separator: " ").map(String.init)
    var n = 0
    func nextPoint() -> NSPoint { let x=Double(expanded[n])!; let y=Double(expanded[n+1])!; n += 2; return NSPoint(x:x,y:y) }
    while n < expanded.count {
        let command=expanded[n]; n += 1
        if command == "M" { p.move(to: nextPoint()) }
        else if command == "C" { let a=nextPoint(), b=nextPoint(), c=nextPoint(); p.curve(to:c,controlPoint1:a,controlPoint2:b) }
        else if command == "Z" { p.close() }
    }
    return p
}
func render(_ size: Int, first: Int, second: Int, tile: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    NSColor.clear.setFill(); NSRect(x:0,y:0,width:size,height:size).fill()
    let transform=NSAffineTransform(); transform.translateX(by:0,yBy:CGFloat(size)); transform.concat()
    let scale=NSAffineTransform(); scale.scaleX(by:CGFloat(size)/1254,yBy:-CGFloat(size)/1254); scale.concat()
    if tile { color(0xfefae0).setFill(); NSBezierPath(roundedRect:NSRect(x:56,y:56,width:1142,height:1142),xRadius:240,yRadius:240).fill() }
    color(first).setFill(); path(upper).fill(); color(second).setFill(); path(lower).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
for (name,a,b,bg,lockup) in [
    ("leaf", "#606c38", "#283618", nil as String?, false),
    ("leaf-mono-dark", "#283618", "#283618", nil, false),
    ("leaf-mono-light", "#fefae0", "#fefae0", nil, false),
    ("leaf-template", "#000000", "#000000", nil, false),
    ("leaf-on-dark", "#dda15e", "#fefae0", "#283618", false),
    ("lockup", "#606c38", "#283618", nil, true),
    ("lockup-light", "#dda15e", "#fefae0", nil, true)
] {
    let data=Data(svg(a,b,background:bg,lockup:lockup).utf8)
    try data.write(to:assets.appendingPathComponent("\(name).svg"))
    try data.write(to:web.appendingPathComponent("\(name).svg"))
}
for (name,a,b,tile) in [("leaf",0x606c38,0x283618,false),("leaf-mono-dark",0x283618,0x283618,false),("leaf-mono-light",0xfefae0,0xfefae0,false),("app-icon",0x606c38,0x283618,true)] {
    try render(1024,first:a,second:b,tile:tile).write(to:assets.appendingPathComponent("\(name).png"))
}
for size in [18,36] { try render(size,first:0,second:0,tile:false).write(to:assets.appendingPathComponent(size == 18 ? "LeafTemplate.png" : "LeafTemplate@2x.png")) }
try render(32,first:0x606c38,second:0x283618,tile:true).write(to:web.appendingPathComponent("favicon-32.png"))
try render(180,first:0x606c38,second:0x283618,tile:true).write(to:web.appendingPathComponent("apple-touch-icon.png"))
let iconset=assets.appendingPathComponent("ResetMe.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for factor in [1,2] {
        let name="icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"
        try render(size*factor,first:0x606c38,second:0x283618,tile:true).write(to:iconset.appendingPathComponent(name))
    }
}
print("Brand SVGs, transparent PNGs, menu templates and iconset generated.")

// Link unfurl artwork: no private usage data or simulated product numbers.
let share = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:630,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:share)
color(0xfefae0).setFill(); NSRect(x:0,y:0,width:1200,height:630).fill()
func label(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, hex: Int) {
    NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color(hex)]).draw(in:NSRect(x:x,y:y,width:width,height:size*2.8))
}
label("ResetMe",x:72,y:421,width:600,size:29,weight:.semibold,hex:0x283618)
label("How much\nhave I got left?",x:68,y:191,width:790,size:75,weight:.medium,hex:0x283618)
label("Claude & Codex usage, at your Mac’s notch.",x:72,y:106,width:820,size:25,weight:.regular,hex:0x606c38)
color(0xbc6c25).setFill(); NSBezierPath(roundedRect:NSRect(x:72,y:80,width:58,height:5),xRadius:2.5,yRadius:2.5).fill()
let leafTransform=NSAffineTransform(); leafTransform.translateX(by:800,yBy:530); leafTransform.scaleX(by:0.28,yBy:-0.28); leafTransform.concat()
color(0x606c38).setFill(); path(upper).fill(); color(0x283618).setFill(); path(lower).fill()
NSGraphicsContext.restoreGraphicsState()
try share.representation(using:.png,properties:[:])!.write(to:web.appendingPathComponent("social-preview-leaf.png"))
