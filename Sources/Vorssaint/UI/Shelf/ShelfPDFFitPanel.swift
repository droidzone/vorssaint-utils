// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Lists the PDF size choices, calculates each one, then replaces the shelf copy.
final class ShelfPDFFitPresenter: ObservableObject {
    static let shared = ShelfPDFFitPresenter()

    @Published var preset: ShelfPDFFitPreset = .low
    @Published var policy = ShelfPDFFitPolicy.standard
    @Published var phase: Phase = .editing
    @Published private(set) var fileCount = 0
    @Published private(set) var currentBytes: Int64 = 0
    @Published private(set) var calculating: ShelfPDFFitPreset?
    @Published private(set) var sizes: [ShelfPDFFitPreset: Int64] = [:]
    @Published private(set) var belowMinimum: Set<ShelfPDFFitPreset> = []

    private var targets: [ShelfImageFitTarget] = []
    private var panel: NSPanel?
    private var generation = 0
    private var holdingShelf = false
    private var cache: [String: ShelfPDFFitResult] = [:]

    enum Phase: Equatable {
        case editing
        case working(done: Int, total: Int)
        case finished(String)
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func present(_ targets: [ShelfImageFitTarget]) {
        guard !targets.isEmpty else { return }
        generation += 1
        self.targets = targets
        fileCount = targets.count
        currentBytes = targets.reduce(Int64(0)) { sum, target in
            sum + Int64((try? target.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        policy = ShelfPDFFitPolicy.load()
        preset = .original
        sizes = [.original: currentBytes]
        belowMinimum = []
        cache = [:]
        calculating = nil
        phase = .editing
        if !holdingShelf {
            ShelfService.shared.beginInteraction()
            holdingShelf = true
        }
        let panel = ensurePanel()
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func select(_ preset: ShelfPDFFitPreset) {
        self.preset = preset
        guard preset.reduces, sizes[preset] == nil, !belowMinimum.contains(preset) else { return }
        calculate(preset)
    }

    func setGrayscale(_ on: Bool) {
        guard policy.grayscale != on else { return }
        policy.grayscale = on
        policy.save()
        sizes = [.original: currentBytes]
        belowMinimum = []
        cache = [:]
        calculating = nil
        generation += 1
        if preset.reduces { calculate(preset) }
    }

    func reduce() {
        let preset = self.preset
        guard preset.reduces, !isWorking else { return }
        let targets = self.targets
        let policy = self.policy
        let imagePolicy = ShelfImageFitPolicy.load()
        generation += 1
        let generation = self.generation
        phase = .working(done: 0, total: targets.count)
        apply(targets, index: 0, preset: preset, policy: policy, imagePolicy: imagePolicy,
              generation: generation, counts: ShelfImageFitCounts())
    }

    func close() {
        generation += 1
        panel?.orderOut(nil)
        if holdingShelf {
            ShelfService.shared.endInteraction()
            holdingShelf = false
        }
    }

    func relayout() {
        guard let panel, panel.isVisible else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        guard size != panel.frame.size else { return }
        var frame = panel.frame
        frame.origin.y -= size.height - frame.height
        frame.size = size
        let visible = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        panel.setFrame(frame, display: true)
    }

    func label(for preset: ShelfPDFFitPreset, strings: ShelfCompressStrings) -> String {
        if calculating == preset { return strings.calculating }
        if belowMinimum.contains(preset) { return strings.belowMinimum }
        if let bytes = sizes[preset] {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        if preset == .original {
            return ByteCountFormatter.string(fromByteCount: currentBytes, countStyle: .file)
        }
        return strings.calculate
    }

    private func calculate(_ preset: ShelfPDFFitPreset) {
        guard let sample = targets.first else { return }
        generation += 1
        let generation = self.generation
        let policy = self.policy
        let imagePolicy = ShelfImageFitPolicy.load()
        calculating = preset
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ShelfPDFFit.encode(url: sample.url, preset: preset,
                                            pdfPolicy: policy, imagePolicy: imagePolicy)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.cache[self.cacheKey(preset, url: sample.url)] = result
                switch result {
                case .unchanged:
                    self.sizes[preset] = self.fileBytes(sample.url)
                case let .file(data):
                    self.sizes[preset] = Int64(data.count)
                case .belowMinimum:
                    self.belowMinimum.insert(preset)
                case .unreadable:
                    break
                }
                if self.calculating == preset { self.calculating = nil }
                self.relayout()
            }
        }
    }

    private func apply(_ targets: [ShelfImageFitTarget],
                       index: Int,
                       preset: ShelfPDFFitPreset,
                       policy: ShelfPDFFitPolicy,
                       imagePolicy: ShelfImageFitPolicy,
                       generation: Int,
                       counts: ShelfImageFitCounts) {
        guard generation == self.generation else { return }
        guard index < targets.count else {
            let strings = ShelfImageFitStrings.localized(L10n.shared.language)
            let limits = ShelfCompressStrings.localized(L10n.shared.language)
            phase = .finished(ShelfImageFit.summary(counts, strings: strings, limits: limits))
            relayout()
            return
        }
        let target = targets[index]
        let key = cacheKey(preset, url: target.url)
        let cached = cache[key]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = cached ?? ShelfPDFFit.encode(url: target.url, preset: preset,
                                                      pdfPolicy: policy, imagePolicy: imagePolicy)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                var counts = counts
                switch result {
                case .unchanged:
                    counts.already += 1
                case .belowMinimum:
                    counts.held += 1
                case .unreadable:
                    counts.failed += 1
                case let .file(data):
                    let name = ShelfPDFFit.outputFileName(for: target.url)
                    if ShelfService.shared.replaceItemWithGeneratedFile(target.id, data: data, named: name) {
                        counts.fitted += 1
                    } else {
                        counts.failed += 1
                    }
                }
                self.phase = .working(done: index + 1, total: targets.count)
                self.apply(targets, index: index + 1, preset: preset, policy: policy,
                           imagePolicy: imagePolicy, generation: generation, counts: counts)
            }
        }
    }

    private func cacheKey(_ preset: ShelfPDFFitPreset, url: URL) -> String {
        "\(preset.rawValue)-\(policy.grayscale)-\(url.path)"
    }

    private func fileBytes(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = ShelfPDFFitWindow(contentRect: .zero,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ShelfPDFFitView(presenter: self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 360, height: 360)
        let screen = NSScreen.withMouse ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private final class ShelfPDFFitWindow: OverlayPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        ShelfPDFFitPresenter.shared.close()
    }
}

struct ShelfPDFFitView: View {
    @ObservedObject var presenter: ShelfPDFFitPresenter
    @ObservedObject private var l10n = L10n.shared

    private var strings: ShelfCompressStrings {
        ShelfCompressStrings.localized(l10n.language)
    }

    private var fit: ShelfImageFitStrings {
        ShelfImageFitStrings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.pdfTitle)
                .font(.system(size: 15, weight: .semibold))
            Text(strings.pdfFlattenNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(sizeLine)
                .font(.system(size: 12, weight: .medium))
            choices
            Toggle(strings.grayscale, isOn: Binding(
                get: { presenter.policy.grayscale },
                set: { presenter.setGrayscale($0) }
            ))
            .disabled(presenter.isWorking)
            if case let .working(done, total) = presenter.phase {
                Text(String(format: fit.workingFormat, done, total))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if case let .finished(message) = presenter.phase, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(16)
        .frame(width: 360)
        .background(HUDBackdrop(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: presenter.phase) { _, _ in presenter.relayout() }
    }

    private var sizeLine: String {
        let bytes = ByteCountFormatter.string(fromByteCount: presenter.currentBytes, countStyle: .file)
        if presenter.fileCount <= 1 { return String(format: fit.nowFormat, bytes) }
        return "\(presenter.fileCount) · \(bytes)"
    }

    private var choices: some View {
        VStack(spacing: 4) {
            ForEach(ShelfPDFFitPreset.allCases) { preset in
                let selected = presenter.preset == preset
                Button {
                    presenter.select(preset)
                } label: {
                    HStack {
                        Text(preset.title(strings))
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        Spacer(minLength: 8)
                        Text(presenter.label(for: preset, strings: strings))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .disabled(presenter.isWorking)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            if case .finished = presenter.phase {
                Button(fit.done) { presenter.close() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(fit.cancel) { presenter.close() }
                    .keyboardShortcut(.cancelAction)
                Button(strings.reduce) { presenter.reduce() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presenter.isWorking || !presenter.preset.reduces || presenter.calculating != nil)
            }
        }
    }
}
