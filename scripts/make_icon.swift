import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// A deliberately simple utility icon: one calorie tally with an add mark.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.12, green: 0.39, blue: 0.34, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(40)
context.strokeEllipse(in: CGRect(x: 225, y: 225, width: 574, height: 574))
context.setLineWidth(48)
context.setLineCap(.round)
context.move(to: CGPoint(x: 385, y: 512)); context.addLine(to: CGPoint(x: 639, y: 512))
context.move(to: CGPoint(x: 512, y: 385)); context.addLine(to: CGPoint(x: 512, y: 639))
context.strokePath()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
