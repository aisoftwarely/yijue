import AppKit
import CoreGraphics

// 用法: swift tools/make_icon.swift <输出路径>
let size = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("无法创建绘图上下文")
}

let s = CGFloat(size)

// 夜空背景：深靛蓝渐变
let topColor = CGColor(colorSpace: colorSpace, components: [0.10, 0.13, 0.34, 1.0])!
let bottomColor = CGColor(colorSpace: colorSpace, components: [0.03, 0.04, 0.12, 1.0])!
let gradient = CGGradient(colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s * 0.35, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// 月亮周围的柔光
let glowColor = CGColor(colorSpace: colorSpace, components: [0.62, 0.66, 1.0, 0.34])!
let clearColor = CGColor(colorSpace: colorSpace, components: [0.62, 0.66, 1.0, 0.0])!
if let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [glowColor, clearColor] as CFArray,
    locations: [0, 1]
) {
    let center = CGPoint(x: 0.64 * s, y: 0.60 * s)
    ctx.drawRadialGradient(
        glow,
        startCenter: center,
        startRadius: 0.10 * s,
        endCenter: center,
        endRadius: 0.44 * s,
        options: [.drawsBeforeStartLocation]
    )
}

// 月牙：大圆减去偏移的圆（even-odd）
let moonCenter = CGPoint(x: 0.64 * s, y: 0.60 * s)
let moonRadius = 0.235 * s
let biteCenter = CGPoint(x: 0.735 * s, y: 0.665 * s)
let biteRadius = 0.212 * s

// 用两段圆弧拼出月牙（大圆的外弧 + 咬掉圆的弧），避免挖洞时破坏背景
let dx = biteCenter.x - moonCenter.x
let dy = biteCenter.y - moonCenter.y
let distance = max(0.001, hypot(dx, dy))
let chordOffset = (moonRadius * moonRadius - biteRadius * biteRadius + distance * distance) / (2 * distance)
let chordHalf = sqrt(max(0, moonRadius * moonRadius - chordOffset * chordOffset))
let ux = dx / distance
let uy = dy / distance
let chordMid = CGPoint(x: moonCenter.x + ux * chordOffset, y: moonCenter.y + uy * chordOffset)
let pointA = CGPoint(x: chordMid.x - uy * chordHalf, y: chordMid.y + ux * chordHalf)
let pointB = CGPoint(x: chordMid.x + uy * chordHalf, y: chordMid.y - ux * chordHalf)

let startA = atan2(pointA.y - moonCenter.y, pointA.x - moonCenter.x)
let endA = atan2(pointB.y - moonCenter.y, pointB.x - moonCenter.x)
let startB = atan2(pointB.y - biteCenter.y, pointB.x - biteCenter.x)
let endB = atan2(pointA.y - biteCenter.y, pointA.x - biteCenter.x)

let moonPath = CGMutablePath()
moonPath.addArc(
    center: moonCenter,
    radius: moonRadius,
    startAngle: startA,
    endAngle: endA,
    clockwise: false
)
moonPath.addArc(
    center: biteCenter,
    radius: biteRadius,
    startAngle: startB,
    endAngle: endB,
    clockwise: true
)
moonPath.closeSubpath()

ctx.saveGState()
ctx.addPath(moonPath)
ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.94, 0.93, 1.0, 1.0])!)
ctx.fillPath()
ctx.restoreGState()

// 三颗星星
func drawStar(center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, alpha])!)
    ctx.fillEllipse(in: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}

drawStar(center: CGPoint(x: 0.255 * s, y: 0.760 * s), radius: 0.020 * s, alpha: 0.95)
drawStar(center: CGPoint(x: 0.360 * s, y: 0.860 * s), radius: 0.012 * s, alpha: 0.75)
drawStar(center: CGPoint(x: 0.175 * s, y: 0.600 * s), radius: 0.010 * s, alpha: 0.55)
drawStar(center: CGPoint(x: 0.505 * s, y: 0.905 * s), radius: 0.008 * s, alpha: 0.45)

// 左侧三个大小递增的 Z，表示“睡”
func drawZ(origin: CGPoint, width: CGFloat, height: CGFloat, lineWidth: CGFloat, alpha: CGFloat) {
    ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.88, 0.90, 1.0, alpha])!)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.move(to: CGPoint(x: origin.x, y: origin.y + height))
    ctx.addLine(to: CGPoint(x: origin.x + width, y: origin.y + height))
    ctx.addLine(to: CGPoint(x: origin.x, y: origin.y))
    ctx.addLine(to: CGPoint(x: origin.x + width, y: origin.y))
    ctx.strokePath()
}

drawZ(origin: CGPoint(x: 0.145 * s, y: 0.335 * s), width: 0.105 * s, height: 0.105 * s, lineWidth: 0.030 * s, alpha: 0.95)
drawZ(origin: CGPoint(x: 0.270 * s, y: 0.245 * s), width: 0.150 * s, height: 0.150 * s, lineWidth: 0.040 * s, alpha: 0.80)
drawZ(origin: CGPoint(x: 0.425 * s, y: 0.120 * s), width: 0.205 * s, height: 0.205 * s, lineWidth: 0.052 * s, alpha: 0.62)

guard let image = ctx.makeImage() else { fatalError("生成图片失败") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 编码失败")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("已生成 \(outputPath)")
