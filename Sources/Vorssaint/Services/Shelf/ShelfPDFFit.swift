// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import PDFKit

enum ShelfPDFFitPreset: String, CaseIterable, Identifiable {
    case original, lossless, maximum, high, medium, low

    var id: String { rawValue }

    var reduces: Bool { self != .original }

    func title(_ strings: ShelfCompressStrings) -> String {
        switch self {
        case .original: return strings.original
        case .lossless: return strings.lossless
        case .maximum: return strings.maximum
        case .high: return strings.high
        case .medium: return strings.medium
        case .low: return strings.low
        }
    }
}

struct ShelfPDFFitLevel: Codable, Equatable {
    var dpi: Int
    var qualityPercent: Int

    func sanitized() -> ShelfPDFFitLevel {
        ShelfPDFFitLevel(dpi: min(600, max(72, dpi > 0 ? dpi : 150)),
                         qualityPercent: min(100, max(40, qualityPercent > 0 ? qualityPercent : 60)))
    }
}

struct ShelfPDFFitPolicy: Codable, Equatable {
    var maximum: ShelfPDFFitLevel
    var high: ShelfPDFFitLevel
    var medium: ShelfPDFFitLevel
    var low: ShelfPDFFitLevel
    var grayscale: Bool

    static let standard = ShelfPDFFitPolicy(
        maximum: ShelfPDFFitLevel(dpi: 300, qualityPercent: 85),
        high: ShelfPDFFitLevel(dpi: 200, qualityPercent: 75),
        medium: ShelfPDFFitLevel(dpi: 150, qualityPercent: 60),
        low: ShelfPDFFitLevel(dpi: 96, qualityPercent: 45),
        grayscale: false)

    func sanitized() -> ShelfPDFFitPolicy {
        var copy = self
        copy.maximum = copy.maximum.sanitized()
        copy.high = copy.high.sanitized()
        copy.medium = copy.medium.sanitized()
        copy.low = copy.low.sanitized()
        return copy
    }

    func level(for preset: ShelfPDFFitPreset) -> ShelfPDFFitLevel? {
        switch preset {
        case .original, .lossless: return nil
        case .maximum: return maximum.sanitized()
        case .high: return high.sanitized()
        case .medium: return medium.sanitized()
        case .low: return low.sanitized()
        }
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(sanitized()) else { return }
        defaults.set(data, forKey: DefaultsKey.shelfPDFFitPolicy)
    }

    static func load(from defaults: UserDefaults = .standard) -> ShelfPDFFitPolicy {
        guard let data = defaults.data(forKey: DefaultsKey.shelfPDFFitPolicy),
              let decoded = try? JSONDecoder().decode(ShelfPDFFitPolicy.self, from: data) else {
            return .standard
        }
        return decoded.sanitized()
    }
}

enum ShelfPDFFitResult: Equatable {
    case unchanged
    case file(Data)
    case belowMinimum
    case unreadable
}

/// Reduces a PDF the way a save-as size list does.
///
/// Original leaves the file alone. Lossless rewrites the pages as vectors, so
/// text stays selectable, and is kept only when the rewrite is actually
/// smaller. The quality presets rasterize each page to JPEG and put it back
/// on the original page size, which means the text is no longer selectable.
/// A checked minimum quality raises the JPEG quality. A checked minimum file
/// size refuses a result that would land under it.
enum ShelfPDFFit {
    static func outputFileName(for source: URL) -> String {
        let png = ShelfImageFit.outputFileName(for: source, format: .png)
        guard png.hasSuffix(".png") else { return "Document.pdf" }
        return String(png.dropLast(4)) + ".pdf"
    }

    static func encode(url: URL,
                       preset: ShelfPDFFitPreset,
                       pdfPolicy: ShelfPDFFitPolicy = .load(),
                       imagePolicy: ShelfImageFitPolicy = .load()) -> ShelfPDFFitResult {
        guard preset != .original else { return .unchanged }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return .unreadable }
        let sourceBytes = fileBytes(url)
        let pdf = pdfPolicy.sanitized()
        let image = imagePolicy.sanitized()
        let written: Data?
        switch preset {
        case .original:
            written = nil
        case .lossless:
            written = rewriteLossless(document)
        case .maximum, .high, .medium, .low:
            guard let level = pdf.level(for: preset) else { return .unreadable }
            let quality = resolvedQuality(level.qualityPercent, imagePolicy: image)
            written = rasterize(document, dpi: level.dpi, quality: quality, grayscale: pdf.grayscale)
        }
        guard let written, !written.isEmpty else { return .unreadable }
        if let minimum = image.minimumFileBytes, Int64(written.count) < minimum {
            return .belowMinimum
        }
        if sourceBytes > 0, Int64(written.count) >= sourceBytes { return .unchanged }
        return .file(written)
    }

    static func resolvedQuality(_ quality: Int, imagePolicy: ShelfImageFitPolicy) -> Int {
        let clean = imagePolicy.sanitized()
        let base = min(100, max(40, quality))
        guard clean.minimumQualityEnabled else { return base }
        return min(100, max(base, clean.minimumQualityPercent))
    }

    private static func fileBytes(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private static func rewriteLossless(_ document: PDFDocument) -> Data? {
        let out = NSMutableData()
        guard let first = document.page(at: 0),
              let consumer = CGDataConsumer(data: out) else { return nil }
        var media = first.bounds(for: .mediaBox)
        guard media.width > 1, media.height > 1,
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let ref = page.pageRef else { continue }
            var box = page.bounds(for: .mediaBox)
            guard box.width > 1, box.height > 1 else { continue }
            context.beginPage(mediaBox: &box)
            context.drawPDFPage(ref)
            context.endPage()
        }
        context.closePDF()
        return out.length > 0 ? out as Data : nil
    }

    private static func rasterize(_ document: PDFDocument,
                                  dpi: Int,
                                  quality: Int,
                                  grayscale: Bool) -> Data? {
        var pages: [ShelfPDFPageImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let rendered = render(page, dpi: dpi, quality: quality, grayscale: grayscale) else { continue }
            pages.append(rendered)
        }
        guard pages.count == document.pageCount, !pages.isEmpty else { return nil }
        return ShelfPDFJPEGDocument.make(pages: pages)
    }

    private static func render(_ page: PDFPage,
                               dpi: Int,
                               quality: Int,
                               grayscale: Bool) -> ShelfPDFPageImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 1, box.height > 1 else { return nil }
        let scale = CGFloat(dpi) / 72
        var pixelWidth = max(1, box.width * scale)
        var pixelHeight = max(1, box.height * scale)
        let longSide = max(pixelWidth, pixelHeight)
        let cap: CGFloat = 4_096
        if longSide > cap {
            let fitted = cap / longSide
            pixelWidth *= fitted
            pixelHeight *= fitted
        }
        let size = CGSize(width: pixelWidth.rounded(), height: pixelHeight.rounded())
        guard MediaSupport.imageRenderSizeIsSafe(size) else { return nil }
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let alpha = grayscale ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: alpha) else { return nil }
        if grayscale {
            context.setFillColor(gray: 1, alpha: 1)
        } else {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        }
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / box.width, y: -CGFloat(height) / box.height)
        context.translateBy(x: -box.origin.x, y: -box.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        guard let image = context.makeImage(),
              let jpeg = ShelfImageFit.encodedImage(image, qualityPercent: quality, format: .jpeg),
              !jpeg.isEmpty else { return nil }
        let gray = grayscale || image.colorSpace?.model == .monochrome
        return ShelfPDFPageImage(jpeg: jpeg,
                                 mediaBox: box,
                                 pixelWidth: image.width,
                                 pixelHeight: image.height,
                                 grayscale: gray)
    }
}

private struct ShelfPDFPageImage {
    var jpeg: Data
    var mediaBox: CGRect
    var pixelWidth: Int
    var pixelHeight: Int
    var grayscale: Bool
}

/// A PDF whose pages are the JPEG bytes themselves, so the file stays near the
/// JPEG size instead of storing the pixels again.
private enum ShelfPDFJPEGDocument {
    static func make(pages: [ShelfPDFPageImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        var slots: [Data?] = Array(repeating: nil, count: 2 + pages.count * 3)
        slots[0] = Data("<< /Type /Catalog /Pages 2 0 R >>".utf8)
        var kids: [Int] = []
        for (offset, page) in pages.enumerated() {
            let pageNumber = 3 + offset * 3
            let contentNumber = pageNumber + 1
            let imageNumber = pageNumber + 2
            kids.append(pageNumber)
            let drawing = "q\n\(decimal(page.mediaBox.width)) 0 0 \(decimal(page.mediaBox.height)) 0 0 cm\n/Im0 Do\nQ\n"
            slots[contentNumber - 1] = stream(Data(drawing.utf8))
            let color = page.grayscale ? "/DeviceGray" : "/DeviceRGB"
            let header = "<< /Type /XObject /Subtype /Image /Width \(page.pixelWidth) /Height \(page.pixelHeight) /ColorSpace \(color) /BitsPerComponent 8 /Filter /DCTDecode /Length \(page.jpeg.count) >>\nstream\n"
            var imageObject = Data(header.utf8)
            imageObject.append(page.jpeg)
            imageObject.append(Data("\nendstream".utf8))
            slots[imageNumber - 1] = imageObject
            let pageObject = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(decimal(page.mediaBox.width)) \(decimal(page.mediaBox.height))] /Contents \(contentNumber) 0 R /Resources << /XObject << /Im0 \(imageNumber) 0 R >> >> >>"
            slots[pageNumber - 1] = Data(pageObject.utf8)
        }
        let kidRefs = kids.map { "\($0) 0 R" }.joined(separator: " ")
        slots[1] = Data("<< /Type /Pages /Kids [\(kidRefs)] /Count \(pages.count) >>".utf8)
        guard slots.allSatisfy({ $0 != nil }) else { return nil }
        return assemble(slots.compactMap { $0 })
    }

    private static func stream(_ payload: Data) -> Data {
        var data = Data("<< /Length \(payload.count) >>\nstream\n".utf8)
        data.append(payload)
        data.append(Data("endstream".utf8))
        return data
    }

    private static func decimal(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func assemble(_ objects: [Data]) -> Data {
        var out = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(index + 1) 0 obj\n".utf8))
            out.append(object)
            out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            table += String(format: "%010d 00000 n \n", offset)
        }
        out.append(Data(table.utf8))
        let trailer = "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(trailer.utf8))
        return out
    }
}
