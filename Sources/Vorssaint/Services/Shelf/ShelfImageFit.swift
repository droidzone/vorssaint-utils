// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A shelf file the compress, convert, or PDF action can rewrite. Leaves that
/// are not the right kind are skipped, including inside a selected pile.
struct ShelfImageFitTarget: Equatable {
    let id: UUID
    let url: URL
}

struct ShelfImageFitLeaf: Equatable {
    var id: UUID
    var isImage: Bool
    var url: URL?
}

enum ShelfImageFitFile: Equatable {
    case alreadyWithinBudget
    case file(Data, ShelfImageConvertFormat)
    case heldForMinimum
    case impossible
    case unreadable
}

struct ShelfImageFitCounts: Equatable {
    var fitted = 0
    var already = 0
    var failed = 0
    var held = 0

    init(fitted: Int = 0, already: Int = 0, failed: Int = 0, held: Int = 0) {
        self.fitted = fitted
        self.already = already
        self.failed = failed
        self.held = held
    }
}

/// Compresses a shelf picture under a chosen size, following the saved ladder.
///
/// The gentler order tries each JPEG quality from high to low, and at each
/// quality tries the current size before the smaller resolution steps. The
/// other order shrinks through those steps first and only then lowers JPEG
/// quality, at the smallest size the steps and the floors still allow.
/// A checked floor is never crossed: the picture is not scaled below the
/// minimum width or height, JPEG quality does not go below the minimum, and
/// a file smaller than the minimum size is not written. Nothing is enlarged.
enum ShelfImageFit {
    static let minimumKilobytes = 10
    static let maximumKilobytes = 20_000
    static let defaultKilobytes = 500
    static let presetKilobytes = [100, 250, 500, 1_000, 2_000]
    static let decodeMaxPixel = 4_096

    static func sanitizedKilobytes(_ value: Int) -> Int {
        min(maximumKilobytes, max(minimumKilobytes, value))
    }

    /// Zero is "never chosen", which is what a missing preference reads as.
    static func storedKilobytes(_ value: Int) -> Int {
        value == 0 ? defaultKilobytes : sanitizedKilobytes(value)
    }

    /// Kilobytes are 1000-based, the way a size limit is written.
    static func targetBytes(kilobytes: Int) -> Int64 {
        Int64(sanitizedKilobytes(kilobytes)) * 1_000
    }

    static func targetBytes(amount: Int, unit: ShelfFitByteUnit) -> Int64 {
        unit.bytes(from: amount)
    }

    static func presetLabel(kilobytes: Int) -> String {
        if kilobytes >= 1_000, kilobytes.isMultiple(of: 1_000) {
            return "\(kilobytes / 1_000) MB"
        }
        return "\(kilobytes) KB"
    }

    static func targets(from leaves: [ShelfImageFitLeaf]) -> [ShelfImageFitTarget] {
        leaves.compactMap { leaf in
            guard let url = leaf.url else { return nil }
            guard leaf.isImage || isImageFile(url) else { return nil }
            return ShelfImageFitTarget(id: leaf.id, url: url)
        }
    }

    static func pdfTargets(from leaves: [ShelfImageFitLeaf]) -> [ShelfImageFitTarget] {
        leaves.compactMap { leaf in
            guard let url = leaf.url, isPDFFile(url) else { return nil }
            return ShelfImageFitTarget(id: leaf.id, url: url)
        }
    }

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) == true
    }

    static func isPDFFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) == true
    }

    static func outputFileName(for source: URL, format: ShelfImageConvertFormat) -> String {
        var base = source.lastPathComponent
        if let dot = base.lastIndex(of: "."), dot != base.startIndex {
            base = String(base[..<dot])
        }
        base = base.replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty || base == "." || base == ".." { base = "Image" }
        if base.count > 180 { base = String(base.prefix(180)) }
        return base + "." + format.fileExtension
    }
}

/// What to do when a rewritten file would keep the source file's name.
/// The default adds `_vor` before the extension. Overwrite reuses the name
/// and keeps the original bytes beside it as `_bak`.
enum ShelfSavedNameStyle: String {
    case addVor = "vor"
    case overwriteOriginal = "overwrite"

    static func current(in defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: DefaultsKey.shelfOutputNaming),
              let style = ShelfSavedNameStyle(rawValue: raw) else { return .addVor }
        return style
    }
}

struct ShelfSavedNamePlan: Equatable {
    var fileName: String
    /// Set only when the new bytes should take the original file's place.
    var backupFileName: String?

    var replacesOriginal: Bool { backupFileName != nil }
}

enum ShelfSavedName {
    static func sameFileName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive]) == .orderedSame
    }

    /// `photo.jpg` with `_vor` becomes `photo_vor.jpg`.
    static func inserting(_ suffix: String, into fileName: String) -> String {
        let name = fileName as NSString
        let ext = name.pathExtension
        let base = name.deletingPathExtension
        guard !ext.isEmpty else { return base + suffix }
        return base + suffix + "." + ext
    }

    /// Leaves a proposed name alone when it already differs from the source.
    /// A matching name either gains `_vor` or stays, with a `_bak` name for the original.
    static func plan(sourceFileName: String,
                     proposed: String,
                     style: ShelfSavedNameStyle = .current()) -> ShelfSavedNamePlan {
        guard sameFileName(sourceFileName, proposed) else {
            return ShelfSavedNamePlan(fileName: proposed, backupFileName: nil)
        }
        switch style {
        case .addVor:
            return ShelfSavedNamePlan(fileName: inserting("_vor", into: proposed), backupFileName: nil)
        case .overwriteOriginal:
            return ShelfSavedNamePlan(fileName: sourceFileName,
                                      backupFileName: inserting("_bak", into: sourceFileName))
        }
    }

    /// `photo_bak.jpg`, or `photo_bak 2.jpg` when that name is already taken.
    static func availableBackupName(_ backupName: String, exists: (String) -> Bool) -> String {
        if !exists(backupName) { return backupName }
        let name = backupName as NSString
        let base = name.deletingPathExtension
        let ext = name.pathExtension
        var index = 2
        while index < 1_000 {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !exists(candidate) { return candidate }
            index += 1
        }
        return backupName
    }

    /// Moves the original aside as the backup name, then writes the new bytes
    /// at the original path. A failed write puts the original back.
    static func replaceOriginal(at source: URL, with data: Data, backupName: String,
                                fileManager: FileManager = .default) -> Bool {
        let directory = source.deletingLastPathComponent()
        let resolved = availableBackupName(backupName) { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        let backup = directory.appendingPathComponent(resolved)
        guard backup.standardizedFileURL.path != source.standardizedFileURL.path,
              fileManager.fileExists(atPath: source.path) else { return false }
        do {
            try fileManager.moveItem(at: source, to: backup)
        } catch {
            return false
        }
        do {
            try data.write(to: source, options: .atomic)
        } catch {
            try? fileManager.moveItem(at: backup, to: source)
            return false
        }
        return true
    }
}

extension ShelfImageFit {
    /// One finished file, written the way the result dialog reads it:
    /// `"photo.png" (100 MB) -> photo (75 KB)`. The new name drops its extension.
    /// A file that was not rewritten keeps the quoted original and a short note.
    static func resultLine(sourceName: String,
                           sourceBytes: Int64,
                           outputName: String? = nil,
                           outputBytes: Int64? = nil,
                           note: String? = nil) -> String {
        let original = "\"\(sourceName)\" (\(byteLabel(sourceBytes)))"
        if let outputName, let outputBytes {
            return "\(original) -> \(resultName(outputName)) (\(byteLabel(outputBytes)))"
        }
        if let note, !note.isEmpty {
            return "\(original) -> \(note)"
        }
        return original
    }

    static func byteLabel(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private static func resultName(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? fileName : base
    }

    static func summary(_ counts: ShelfImageFitCounts, strings: ShelfImageFitStrings) -> String {
        var parts: [String] = []
        switch counts.fitted {
        case 0: break
        case 1: parts.append(strings.fittedOne)
        default: parts.append(String(format: strings.fittedMany, counts.fitted))
        }
        switch counts.already {
        case 0: break
        case 1: parts.append(strings.alreadyOne)
        default: parts.append(String(format: strings.alreadyMany, counts.already))
        }
        switch counts.failed {
        case 0: break
        case 1: parts.append(strings.failedOne)
        default: parts.append(String(format: strings.failedMany, counts.failed))
        }
        return parts.joined(separator: "\n")
    }

    static func summary(_ counts: ShelfImageFitCounts,
                        strings: ShelfImageFitStrings,
                        limits: ShelfCompressStrings) -> String {
        var parts = summary(counts, strings: strings)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        switch counts.held {
        case 0: break
        case 1: parts.append(limits.heldOne)
        default: parts.append(String(format: limits.heldMany, counts.held))
        }
        return parts.joined(separator: "\n")
    }

    /// Walks `steps` from least degradation to most. A measurement under the
    /// minimum file size is skipped. The first step that is still at or under
    /// the target wins. If the only steps under the target break that floor,
    /// the original stays.
    static func choose(sourceBytes: Int64,
                       targetBytes: Int64,
                       steps: [ShelfImageFitStep],
                       minimumFileBytes: Int64?,
                       measure: (ShelfImageFitStep) -> Int64?) -> ShelfImageFitChoice {
        guard targetBytes > 0 else { return .impossible }
        if sourceBytes > 0, sourceBytes <= targetBytes { return .alreadyWithinBudget }
        var sawUnderTargetBelowMinimum = false
        for step in steps {
            guard let bytes = measure(step), bytes > 0 else { continue }
            if let minimumFileBytes, bytes < minimumFileBytes {
                if bytes <= targetBytes { sawUnderTargetBelowMinimum = true }
                continue
            }
            if bytes <= targetBytes { return .step(step) }
        }
        if sawUnderTargetBelowMinimum { return .heldForMinimum }
        return .impossible
    }

    static func encode(url: URL,
                       targetBytes: Int64,
                       policy: ShelfImageFitPolicy = .load()) -> ShelfImageFitFile {
        guard targetBytes > 0 else { return .impossible }
        let sourceBytes = fileBytes(url)
        let clean = policy.sanitized()
        if sourceBytes > 0, sourceBytes <= targetBytes { return .alreadyWithinBudget }
        guard let source = MediaSupport.imageThumbnail(at: url, maxPixel: decodeMaxPixel) else {
            return .unreadable
        }
        let planned = clean.steps(for: CGSize(width: source.width, height: source.height))
        var rendered: [Int: CGImage] = [:]
        var encoded: [ShelfImageFitStep: (Data, ShelfImageConvertFormat)] = [:]
        let outcome = choose(sourceBytes: sourceBytes,
                             targetBytes: targetBytes,
                             steps: planned,
                             minimumFileBytes: clean.minimumFileBytes) { step in
            if let cached = encoded[step] { return Int64(cached.0.count) }
            guard let written = write(source, step: step, sourceURL: url, policy: clean, cache: &rendered) else {
                return nil
            }
            encoded[step] = written
            return Int64(written.0.count)
        }
        switch outcome {
        case .alreadyWithinBudget:
            return .alreadyWithinBudget
        case .heldForMinimum:
            return .heldForMinimum
        case .impossible:
            return .impossible
        case let .step(step):
            guard let written = encoded[step] ?? write(source, step: step, sourceURL: url, policy: clean, cache: &rendered),
                  Int64(written.0.count) <= targetBytes else { return .impossible }
            if let minimum = clean.minimumFileBytes, Int64(written.0.count) < minimum {
                return .heldForMinimum
            }
            return .file(written.0, written.1)
        }
    }

    /// Rewrites the picture in `format` at its current size. Lossy formats use
    /// `qualityPercent`. The caller applies the quality floor first.
    static func convert(url: URL,
                        to format: ShelfImageConvertFormat,
                        qualityPercent: Int) -> ShelfImageFitFile {
        guard ShelfImageConvertFormat.canEncode(format),
              let source = MediaSupport.imageThumbnail(at: url, maxPixel: decodeMaxPixel),
              let data = encodedImage(source, qualityPercent: qualityPercent, format: format),
              !data.isEmpty else { return .unreadable }
        return .file(data, format)
    }

    static func encodedImage(_ image: CGImage,
                             qualityPercent: Int,
                             format: ShelfImageConvertFormat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,
                                                                 format.typeIdentifier as CFString,
                                                                 1, nil) else { return nil }
        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = qualityFactor(qualityPercent)
        }
        if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: 5,
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
        return data as Data
    }

    private static func write(_ image: CGImage,
                              step: ShelfImageFitStep,
                              sourceURL: URL,
                              policy: ShelfImageFitPolicy,
                              cache: inout [Int: CGImage]) -> (Data, ShelfImageConvertFormat)? {
        let longSide: Int
        let format: ShelfImageConvertFormat
        let quality: Int
        switch step {
        case let .resize(side):
            longSide = side
            format = ShelfImageConvertFormat.container(for: sourceURL)
            quality = policy.usableQualities.first ?? policy.effectiveConversionQuality
        case let .jpeg(side, qualityPercent):
            longSide = side
            format = .jpeg
            quality = qualityPercent
        }
        let bitmap = cache[longSide] ?? render(image, longSide: longSide)
        guard let bitmap else { return nil }
        cache[longSide] = bitmap
        guard let data = encodedImage(bitmap, qualityPercent: quality, format: format), !data.isEmpty else {
            return nil
        }
        return (data, format)
    }

    private static func qualityFactor(_ percent: Int) -> Double {
        Double(min(100, max(1, percent))) / 100
    }

    private static func fileBytes(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    /// Scales so the long side is at most `longSide`, never enlarging, and
    /// draws onto white so a transparent picture can become a JPEG.
    private static func render(_ image: CGImage, longSide: Int) -> CGImage? {
        let source = CGSize(width: image.width, height: image.height)
        let target = MediaImageResizeMode.maxDimension(max(1, longSide)).targetSize(for: source)
        guard MediaSupport.imageRenderSizeIsSafe(target) else { return nil }
        let width = Int(target.width.rounded())
        let height = Int(target.height.rounded())
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
