// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Kilobytes and megabytes are 1000-based, the way a size limit is written.
enum ShelfFitByteUnit: String, Codable, CaseIterable, Identifiable {
    case kilobyte
    case megabyte

    var id: String { rawValue }

    var multiplier: Int64 { self == .kilobyte ? 1_000 : 1_000_000 }
    var minimum: Int { self == .kilobyte ? 10 : 1 }
    var maximum: Int { self == .kilobyte ? 20_000 : 50 }
    var step: Int { self == .kilobyte ? 50 : 1 }
    var label: String { self == .kilobyte ? "KB" : "MB" }

    func sanitized(_ value: Int) -> Int {
        min(maximum, max(minimum, value == 0 ? minimum : value))
    }

    func bytes(from amount: Int) -> Int64 {
        Int64(sanitized(amount)) * multiplier
    }

    func amount(forBytes bytes: Int64) -> Int {
        guard bytes > 0 else { return minimum }
        let raw = (Double(bytes) / Double(multiplier)).rounded(.toNearestOrAwayFromZero)
        return sanitized(Int(raw))
    }

    /// A missing unit means the older kilobyte preference is still the choice.
    static func stored(from defaults: UserDefaults = .standard) -> (amount: Int, unit: ShelfFitByteUnit) {
        if let raw = defaults.string(forKey: DefaultsKey.shelfImageFitUnit),
           let unit = ShelfFitByteUnit(rawValue: raw) {
            let amount = defaults.integer(forKey: DefaultsKey.shelfImageFitAmount)
            let fallback = unit == .kilobyte ? ShelfImageFit.defaultKilobytes : unit.minimum
            return (unit.sanitized(amount == 0 ? fallback : amount), unit)
        }
        let kilobytes = ShelfImageFit.storedKilobytes(
            defaults.integer(forKey: DefaultsKey.shelfImageFitKilobytes))
        return (kilobytes, .kilobyte)
    }

    func save(amount: Int, to defaults: UserDefaults = .standard) {
        let clean = sanitized(amount)
        defaults.set(clean, forKey: DefaultsKey.shelfImageFitAmount)
        defaults.set(rawValue, forKey: DefaultsKey.shelfImageFitUnit)
        let kilobytes = ShelfFitByteUnit.kilobyte.amount(forBytes: bytes(from: clean))
        defaults.set(ShelfImageFit.sanitizedKilobytes(kilobytes), forKey: DefaultsKey.shelfImageFitKilobytes)
    }
}

struct ShelfFitPreset: Equatable, Identifiable {
    var amount: Int
    var unit: ShelfFitByteUnit

    var id: String { "\(amount)-\(unit.rawValue)" }

    var label: String { "\(amount) \(unit.label)" }

    static let all: [ShelfFitPreset] = [
        ShelfFitPreset(amount: 100, unit: .kilobyte),
        ShelfFitPreset(amount: 250, unit: .kilobyte),
        ShelfFitPreset(amount: 500, unit: .kilobyte),
        ShelfFitPreset(amount: 1, unit: .megabyte),
        ShelfFitPreset(amount: 2, unit: .megabyte),
    ]
}

enum ShelfImageFitOrder: String, Codable, CaseIterable, Identifiable {
    /// Try a milder JPEG quality at a larger size before a smaller picture.
    case protectDetail
    /// Shrink through the resolution steps first, then lower JPEG quality
    /// only at the smallest size those steps allow.
    case shrinkFirst

    var id: String { rawValue }
}

enum ShelfImageFitStep: Hashable {
    /// Smaller long side, still in the file's own format.
    case resize(longSide: Int)
    case jpeg(longSide: Int, qualityPercent: Int)
}

enum ShelfImageFitChoice: Equatable {
    case alreadyWithinBudget
    case step(ShelfImageFitStep)
    /// A step could land under the target only by going under the minimum file size.
    case heldForMinimum
    case impossible
}

/// Formats a shelf picture can be rewritten as. Kept separate from the media
/// workspace's format list, which is a smaller set.
enum ShelfImageConvertFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg, png, tiff, heic, gif, bmp, jpeg2000

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heic: return "heic"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .jpeg2000: return "jp2"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .tiff: return UTType.tiff.identifier
        case .heic: return UTType.heic.identifier
        case .gif: return UTType.gif.identifier
        case .bmp: return UTType.bmp.identifier
        case .jpeg2000:
            return UTType(filenameExtension: "jp2")?.identifier ?? "public.jpeg-2000"
        }
    }

    var isLossy: Bool {
        switch self {
        case .jpeg, .heic, .jpeg2000: return true
        case .png, .tiff, .gif, .bmp: return false
        }
    }

    func matches(extension ext: String) -> Bool {
        switch self {
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .tiff: return ext == "tif" || ext == "tiff"
        case .jpeg2000: return ext == "jp2" || ext == "j2k" || ext == "jpf"
        default: return ext == fileExtension
        }
    }

    func title(_ strings: ShelfCompressStrings) -> String {
        switch self {
        case .jpeg: return strings.jpeg
        case .png: return strings.png
        case .tiff: return strings.tiff
        case .heic: return strings.heic
        case .gif: return strings.gif
        case .bmp: return strings.bmp
        case .jpeg2000: return strings.jpeg2000
        }
    }

    static func canEncode(_ format: ShelfImageConvertFormat) -> Bool {
        CGImageDestinationCreateWithData(NSMutableData(),
                                        format.typeIdentifier as CFString,
                                        1, nil) != nil
    }

    /// Formats this Mac can actually write. JPEG 2000 is omitted when it cannot.
    static let writable: [ShelfImageConvertFormat] = allCases.filter(canEncode)

    static func container(for url: URL) -> ShelfImageConvertFormat {
        let ext = url.pathExtension.lowercased()
        if let match = allCases.first(where: { $0.matches(extension: ext) }), canEncode(match) {
            return match
        }
        return .jpeg
    }
}

/// The shelf's picture ladder, including the optional floors. A floor is used
/// only while its checkbox is on. Empty lists fall back to the standard steps
/// so a saved policy can never run with nothing to try.
struct ShelfImageFitPolicy: Codable, Equatable {
    var order: ShelfImageFitOrder
    var resolutions: [Int]
    var qualities: [Int]
    var minimumWidthEnabled: Bool
    var minimumWidth: Int
    var minimumHeightEnabled: Bool
    var minimumHeight: Int
    var minimumQualityEnabled: Bool
    var minimumQualityPercent: Int
    var minimumFileSizeEnabled: Bool
    var minimumFileSizeValue: Int
    var minimumFileSizeUnit: ShelfFitByteUnit
    var conversionQualityPercent: Int

    static let resolutionChoices = [3840, 1920, 1280, 640]
    static let qualityChoices = [90, 80, 70, 60, 50]

    static let standard = ShelfImageFitPolicy(
        order: .protectDetail,
        resolutions: [3840, 1920, 1280, 640],
        qualities: [90, 80, 70],
        minimumWidthEnabled: false,
        minimumWidth: 1280,
        minimumHeightEnabled: false,
        minimumHeight: 720,
        minimumQualityEnabled: false,
        minimumQualityPercent: 70,
        minimumFileSizeEnabled: false,
        minimumFileSizeValue: 100,
        minimumFileSizeUnit: .kilobyte,
        conversionQualityPercent: 90)

    func sanitized() -> ShelfImageFitPolicy {
        var copy = self
        copy.resolutions = Self.unique(copy.resolutions.filter { (64...8_000).contains($0) }).sorted(by: >)
        if copy.resolutions.isEmpty { copy.resolutions = Self.standard.resolutions }
        copy.qualities = Self.unique(copy.qualities.filter { (40...100).contains($0) }).sorted(by: >)
        if copy.qualities.isEmpty { copy.qualities = Self.standard.qualities }
        copy.minimumWidth = Self.clampedPixel(copy.minimumWidth, fallback: Self.standard.minimumWidth)
        copy.minimumHeight = Self.clampedPixel(copy.minimumHeight, fallback: Self.standard.minimumHeight)
        copy.minimumQualityPercent = Self.clampedPercent(copy.minimumQualityPercent,
                                                         fallback: Self.standard.minimumQualityPercent)
        copy.minimumFileSizeValue = copy.minimumFileSizeUnit.sanitized(
            copy.minimumFileSizeValue == 0
                ? Self.standard.minimumFileSizeValue
                : copy.minimumFileSizeValue)
        copy.conversionQualityPercent = Self.clampedPercent(copy.conversionQualityPercent,
                                                            fallback: Self.standard.conversionQualityPercent)
        return copy
    }

    /// JPEG qualities the ladder may use, highest first. The minimum-quality
    /// checkbox drops anything below it. With the checkbox off, the stored
    /// percent is ignored.
    var usableQualities: [Int] {
        let clean = sanitized()
        var list = clean.qualities
        if clean.minimumQualityEnabled {
            list = list.filter { $0 >= clean.minimumQualityPercent }
            if list.isEmpty { list = [clean.minimumQualityPercent] }
        }
        return list.sorted(by: >)
    }

    var usableResolutions: [Int] {
        sanitized().resolutions.sorted(by: >)
    }

    var minimumFileBytes: Int64? {
        let clean = sanitized()
        guard clean.minimumFileSizeEnabled else { return nil }
        return clean.minimumFileSizeUnit.bytes(from: clean.minimumFileSizeValue)
    }

    /// Lossy conversion uses this. A checked quality floor raises it when the
    /// conversion quality sits below that floor.
    var effectiveConversionQuality: Int {
        let clean = sanitized()
        if clean.minimumQualityEnabled {
            return max(clean.conversionQualityPercent, clean.minimumQualityPercent)
        }
        return clean.conversionQualityPercent
    }

    func resolutionTitle(_ value: Int) -> String {
        switch value {
        case 3840: return "4K"
        case 1920: return "1080p"
        case 1280: return "720p"
        case 640: return "VGA"
        default: return "\(value)"
        }
    }

    /// Least degradation first. The current size is always allowed: a floor
    /// stops a shrink, and the picture is never enlarged to meet it.
    func steps(for source: CGSize) -> [ShelfImageFitStep] {
        let clean = sanitized()
        let sourceSize = CGSize(width: max(1, abs(source.width)), height: max(1, abs(source.height)))
        let sourceLong = max(1, Int(max(sourceSize.width, sourceSize.height).rounded()))
        let caps = clean.usableResolutions.filter { longSide in
            longSide < sourceLong && clean.allowsShrink(to: longSide, source: sourceSize)
        }
        let qualities = clean.usableQualities
        switch clean.order {
        case .protectDetail:
            let sizes = [sourceLong] + caps
            var planned: [ShelfImageFitStep] = []
            for quality in qualities {
                for size in sizes {
                    planned.append(.jpeg(longSide: size, qualityPercent: quality))
                }
            }
            return planned
        case .shrinkFirst:
            var planned = caps.map { ShelfImageFitStep.resize(longSide: $0) }
            let finalSide = caps.last ?? sourceLong
            for quality in qualities {
                planned.append(.jpeg(longSide: finalSide, qualityPercent: quality))
            }
            return planned
        }
    }

    func save(to defaults: UserDefaults = .standard) {
        let clean = sanitized()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: DefaultsKey.shelfImageFitPolicy)
    }

    static func load(from defaults: UserDefaults = .standard) -> ShelfImageFitPolicy {
        guard let data = defaults.data(forKey: DefaultsKey.shelfImageFitPolicy),
              let decoded = try? JSONDecoder().decode(ShelfImageFitPolicy.self, from: data) else {
            return .standard
        }
        return decoded.sanitized()
    }

    private func allowsShrink(to longSide: Int, source: CGSize) -> Bool {
        let size = MediaImageResizeMode.maxDimension(longSide).targetSize(for: source)
        if minimumWidthEnabled, size.width < CGFloat(Self.clampedPixel(minimumWidth, fallback: Self.standard.minimumWidth)) {
            return false
        }
        if minimumHeightEnabled, size.height < CGFloat(Self.clampedPixel(minimumHeight, fallback: Self.standard.minimumHeight)) {
            return false
        }
        return true
    }

    private static func clampedPixel(_ value: Int, fallback: Int) -> Int {
        let clean = value > 0 ? value : fallback
        return min(8_000, max(64, clean))
    }

    private static func clampedPercent(_ value: Int, fallback: Int) -> Int {
        let clean = value > 0 ? value : fallback
        return min(100, max(40, clean))
    }

    private static func unique(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }
}
