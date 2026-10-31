// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shelf settings for the picture ladder, its optional floors, and PDF sizes.
struct ShelfCompressionSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var image = ShelfImageFitPolicy.load()
    @State private var pdf = ShelfPDFFitPolicy.load()

    private var strings: ShelfCompressStrings {
        ShelfCompressStrings.localized(l10n.language)
    }

    var body: some View {
        Group {
            Section(strings.section) {
                Picker(strings.order, selection: $image.order) {
                    Text(strings.protectDetail).tag(ShelfImageFitOrder.protectDetail)
                    Text(strings.shrinkFirst).tag(ShelfImageFitOrder.shrinkFirst)
                }
                Text(image.order == .protectDetail ? strings.protectDetailCaption : strings.shrinkFirstCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(strings.resolutions)
                    .font(.callout.weight(.semibold))
                ForEach(ShelfImageFitPolicy.resolutionChoices, id: \.self) { value in
                    Toggle(image.resolutionTitle(value), isOn: resolutionBinding(value))
                }
                Text(strings.qualities)
                    .font(.callout.weight(.semibold))
                ForEach(ShelfImageFitPolicy.qualityChoices, id: \.self) { value in
                    Toggle("\(value)%", isOn: qualityBinding(value))
                }
                Text(strings.limitsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                pixelRow(strings.minimumWidth,
                         enabled: $image.minimumWidthEnabled,
                         value: $image.minimumWidth)
                pixelRow(strings.minimumHeight,
                         enabled: $image.minimumHeightEnabled,
                         value: $image.minimumHeight)
                HStack {
                    Toggle(strings.minimumQuality, isOn: $image.minimumQualityEnabled)
                    TextField("%", value: $image.minimumQualityPercent, format: .number)
                        .frame(width: 64)
                        .disabled(!image.minimumQualityEnabled)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Toggle(strings.minimumFileSize, isOn: $image.minimumFileSizeEnabled)
                    TextField(image.minimumFileSizeUnit.label,
                              value: $image.minimumFileSizeValue,
                              format: .number)
                        .frame(width: 72)
                        .disabled(!image.minimumFileSizeEnabled)
                    Picker(strings.minimumFileSize, selection: fileUnitBinding) {
                        ForEach(ShelfFitByteUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .disabled(!image.minimumFileSizeEnabled)
                }
                Stepper(value: $image.conversionQualityPercent, in: 40...100, step: 5) {
                    Text("\(strings.conversionQuality): \(image.conversionQualityPercent)%")
                }
                Text(strings.conversionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: image) { _, new in
                let clean = new.sanitized()
                if clean != new { image = clean } else { clean.save() }
            }

            Section(strings.pdfSection) {
                Text(strings.pdfCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(strings.grayscale, isOn: $pdf.grayscale)
                Text(strings.grayscaleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                levelRow(strings.maximum, level: $pdf.maximum)
                levelRow(strings.high, level: $pdf.high)
                levelRow(strings.medium, level: $pdf.medium)
                levelRow(strings.low, level: $pdf.low)
            }
            .onChange(of: pdf) { _, new in
                let clean = new.sanitized()
                if clean != new { pdf = clean } else { clean.save() }
            }
        }
        .onAppear {
            image = ShelfImageFitPolicy.load()
            pdf = ShelfPDFFitPolicy.load()
        }
    }

    private var fileUnitBinding: Binding<ShelfFitByteUnit> {
        Binding(
            get: { image.minimumFileSizeUnit },
            set: { unit in
                let bytes = image.minimumFileSizeUnit.bytes(from: image.minimumFileSizeValue)
                image.minimumFileSizeUnit = unit
                image.minimumFileSizeValue = unit.amount(forBytes: bytes)
            }
        )
    }

    private func resolutionBinding(_ value: Int) -> Binding<Bool> {
        Binding(
            get: { image.resolutions.contains(value) },
            set: { on in
                if on {
                    if !image.resolutions.contains(value) { image.resolutions.append(value) }
                } else if image.resolutions.count > 1 {
                    image.resolutions.removeAll { $0 == value }
                }
                image.resolutions.sort(by: >)
            }
        )
    }

    private func qualityBinding(_ value: Int) -> Binding<Bool> {
        Binding(
            get: { image.qualities.contains(value) },
            set: { on in
                if on {
                    if !image.qualities.contains(value) { image.qualities.append(value) }
                } else if image.qualities.count > 1 {
                    image.qualities.removeAll { $0 == value }
                }
                image.qualities.sort(by: >)
            }
        )
    }

    private func pixelRow(_ title: String,
                          enabled: Binding<Bool>,
                          value: Binding<Int>) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
            TextField(strings.pixels, value: value, format: .number)
                .frame(width: 72)
                .disabled(!enabled.wrappedValue)
            Text(strings.pixels)
                .foregroundStyle(.secondary)
        }
    }

    private func levelRow(_ title: String, level: Binding<ShelfPDFFitLevel>) -> some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            TextField(strings.dpi, value: level.dpi, format: .number)
                .frame(width: 64)
            Text(strings.dpi)
                .foregroundStyle(.secondary)
            TextField(strings.pdfQuality, value: level.qualityPercent, format: .number)
                .frame(width: 56)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }
}
