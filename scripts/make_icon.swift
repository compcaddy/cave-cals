import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Render the same black vector used in the app onto an opaque white App Store icon.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Shared/CaveIcons.xcassets/CaveMeal.imageset/CaveMeal.pdf")
let page = CGPDFDocument(source as CFURL)!.page(at: 1)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let frame = CGRect(x: 154, y: 154, width: 716, height: 716)
let bounds = page.getBoxRect(.mediaBox)
let scale = min(frame.width / bounds.width, frame.height / bounds.height)
context.translateBy(x: frame.midX - bounds.width * scale / 2, y: frame.midY - bounds.height * scale / 2)
context.scaleBy(x: scale, y: scale)
context.translateBy(x: -bounds.minX, y: -bounds.minY)
context.drawPDFPage(page)
let output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
