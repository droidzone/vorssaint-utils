// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Asks for a size, then rewrites the shelf's pictures so each one lands under it.
final class ShelfImageFitPresenter: ObservableObject {
    static let shared = ShelfImageFitPresenter()

    @Published var amount = ShelfImageFit.defaultKilobytes
    @Published var unit = ShelfFitByteUnit.kilobyte
    @Published var policy = ShelfImageFitPolicy.standard
    @Published var phase: Phase = .editing
    @Published private(set) var imageCount = 0
    @Published private(set) var currentBytes: Int64 = 0

    private var targets: [ShelfImageFitTarget] = []
    private var panel: NSPanel?
    private var generation = 0
    private var holdingShelf = false

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
        imageCount = targets.count
        currentBytes = targets.reduce(Int64(0)) { sum, target in
            let size = (try? target.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        }
        let stored = ShelfFitByteUnit.stored()
        amount = stored.amount
        unit = stored.unit
        policy = ShelfImageFitPolicy.load()
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

    func compress() {
        let cleanUnit = unit
        let chosen = cleanUnit.sanitized(amount)
        amount = chosen
        unit = cleanUnit
        cleanUnit.save(amount: chosen)
        policy = policy.sanitized()
        policy.save()
        let budget = ShelfImageFit.targetBytes(amount: chosen, unit: cleanUnit)
        let targets = self.targets
        let policy = self.policy
        generation += 1
        let generation = self.generation
        phase = .working(done: 0, total: targets.count)
        compress(targets, index: 0, budget: budget, policy: policy, generation: generation,
                 counts: ShelfImageFitCounts(), lines: [])
    }

    func setUnit(_ newUnit: ShelfFitByteUnit) {
        guard newUnit != unit else { return }
        let bytes = unit.bytes(from: amount)
        unit = newUnit
        amount = newUnit.amount(forBytes: bytes)
    }

    func editPolicy(_ update: (inout ShelfImageFitPolicy) -> Void) {
        var copy = policy
        update(&copy)
        policy = copy
        copy.save()
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
        // Keep the top edge put while the progress line appears and leaves.
        frame.origin.y -= size.height - frame.height
        frame.size = size
        let visible = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        panel.setFrame(frame, display: true)
    }

    private func compress(_ targets: [ShelfImageFitTarget],
                          index: Int,
                          budget: Int64,
                          policy: ShelfImageFitPolicy,
                          generation: Int,
                          counts: ShelfImageFitCounts,
                          lines: [String]) {
        guard generation == self.generation else { return }
        guard index < targets.count else {
            ShelfFitResultDialog.show(lines)
            close()
            return
        }
        let target = targets[index]
        let sourceName = target.url.lastPathComponent
        let sourceBytes = Int64((try? target.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let encoded = ShelfImageFit.encode(url: target.url, targetBytes: budget, policy: policy)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                let strings = ShelfImageFitStrings.localized(L10n.shared.language)
                let limits = ShelfCompressStrings.localized(L10n.shared.language)
                var counts = counts
                var lines = lines
                switch encoded {
                case .alreadyWithinBudget:
                    counts.already += 1
                    lines.append(ShelfImageFit.resultLine(sourceName: sourceName,
                                                          sourceBytes: sourceBytes,
                                                          note: strings.alreadyOne))
                case .heldForMinimum:
                    counts.held += 1
                    lines.append(ShelfImageFit.resultLine(sourceName: sourceName,
                                                          sourceBytes: sourceBytes,
                                                          note: limits.heldOne))
                case .impossible, .unreadable:
                    counts.failed += 1
                    lines.append(ShelfImageFit.resultLine(sourceName: sourceName,
                                                          sourceBytes: sourceBytes,
                                                          note: strings.failedOne))
                case let .file(data, format):
                    let proposed = ShelfImageFit.outputFileName(for: target.url, format: format)
                    if let name = ShelfService.shared.installFittedFile(target.id, data: data, proposedName: proposed) {
                        counts.fitted += 1
                        lines.append(ShelfImageFit.resultLine(sourceName: sourceName,
                                                              sourceBytes: sourceBytes,
                                                              outputName: name,
                                                              outputBytes: Int64(data.count)))
                    } else {
                        counts.failed += 1
                        lines.append(ShelfImageFit.resultLine(sourceName: sourceName,
                                                              sourceBytes: sourceBytes,
                                                              note: strings.failedOne))
                    }
                }
                self.phase = .working(done: index + 1, total: targets.count)
                self.compress(targets, index: index + 1, budget: budget, policy: policy,
                              generation: generation, counts: counts, lines: lines)
            }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = ShelfImageFitWindow(contentRect: .zero,
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
        let host = NSHostingController(rootView: ShelfImageFitView(presenter: self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 340, height: 280)
        let screen = NSScreen.withMouse ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

enum ShelfImageConvert {
    static func start(_ targets: [ShelfImageFitTarget], format: ShelfImageConvertFormat) {
        guard !targets.isEmpty else { return }
        let quality = ShelfImageFitPolicy.load().effectiveConversionQuality
        convert(targets, index: 0, format: format, quality: quality, fitted: 0, failed: 0)
    }

    private static func convert(_ targets: [ShelfImageFitTarget],
                                index: Int,
                                format: ShelfImageConvertFormat,
                                quality: Int,
                                fitted: Int,
                                failed: Int) {
        guard index < targets.count else {
            let strings = ShelfCompressStrings.localized(L10n.shared.language)
            var parts: [String] = []
            switch fitted {
            case 0: break
            case 1: parts.append(strings.convertedOne)
            default: parts.append(String(format: strings.convertedMany, fitted))
            }
            switch failed {
            case 0: break
            case 1: parts.append(strings.convertFailedOne)
            default: parts.append(String(format: strings.convertFailedMany, failed))
            }
            let message = parts.joined(separator: "\n")
            guard !message.isEmpty else { return }
            QuickToolHUD.show(icon: "photo", message: message)
            return
        }
        let target = targets[index]
        DispatchQueue.global(qos: .userInitiated).async {
            let encoded = ShelfImageFit.convert(url: target.url, to: format, qualityPercent: quality)
            DispatchQueue.main.async {
                var nextFitted = fitted
                var nextFailed = failed
                if case let .file(data, written) = encoded {
                    let proposed = ShelfImageFit.outputFileName(for: target.url, format: written)
                    if ShelfService.shared.installFittedFile(target.id, data: data, proposedName: proposed) != nil {
                        nextFitted += 1
                    } else {
                        nextFailed += 1
                    }
                } else {
                    nextFailed += 1
                }
                convert(targets, index: index + 1, format: format, quality: quality,
                        fitted: nextFitted, failed: nextFailed)
            }
        }
    }
}

private final class ShelfImageFitWindow: OverlayPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        ShelfImageFitPresenter.shared.close()
    }
}

struct ShelfImageFitView: View {
    @ObservedObject var presenter: ShelfImageFitPresenter
    @ObservedObject private var l10n = L10n.shared

    private var strings: ShelfImageFitStrings {
        ShelfImageFitStrings.localized(l10n.language)
    }

    private var limits: ShelfCompressStrings {
        ShelfCompressStrings.localized(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.title)
                .font(.system(size: 15, weight: .semibold))
            Text(strings.caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(sizeLine)
                .font(.system(size: 12, weight: .medium))
            Text(strings.target)
                .font(.system(size: 12, weight: .semibold))
            presetRow
            sizeField
            limitFields
            if case let .working(done, total) = presenter.phase {
                Text(String(format: strings.workingFormat, done, total))
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
        .frame(width: 380)
        .background(HUDBackdrop(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: presenter.phase) { _, _ in presenter.relayout() }
    }

    private var sizeLine: String {
        let bytes = ByteCountFormatter.string(fromByteCount: presenter.currentBytes, countStyle: .file)
        if presenter.imageCount <= 1 {
            return String(format: strings.nowFormat, bytes)
        }
        return String(format: strings.imagesFormat, presenter.imageCount, bytes)
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(ShelfFitPreset.all) { preset in
                let selected = presenter.amount == preset.amount && presenter.unit == preset.unit
                Button {
                    presenter.amount = preset.amount
                    presenter.unit = preset.unit
                } label: {
                    Text(preset.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected
                                      ? Color.accentColor.opacity(0.28)
                                      : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(presenter.isWorking)
            }
        }
    }

    private var sizeField: some View {
        HStack(spacing: 8) {
            TextField(presenter.unit.label, value: $presenter.amount, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .disabled(presenter.isWorking)
            Picker(limits.section, selection: Binding(
                get: { presenter.unit },
                set: { presenter.setUnit($0) }
            )) {
                ForEach(ShelfFitByteUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 72)
            .disabled(presenter.isWorking)
            Stepper("", value: $presenter.amount,
                    in: presenter.unit.minimum...presenter.unit.maximum,
                    step: presenter.unit.step)
                .labelsHidden()
                .disabled(presenter.isWorking)
            Spacer(minLength: 0)
        }
    }

    private var limitFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(limits.limitsCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            pixelLimit(title: limits.minimumWidth,
                       enabled: presenter.policy.minimumWidthEnabled,
                       value: presenter.policy.minimumWidth) { enabled, value in
                presenter.editPolicy {
                    $0.minimumWidthEnabled = enabled
                    $0.minimumWidth = value
                }
            }
            pixelLimit(title: limits.minimumHeight,
                       enabled: presenter.policy.minimumHeightEnabled,
                       value: presenter.policy.minimumHeight) { enabled, value in
                presenter.editPolicy {
                    $0.minimumHeightEnabled = enabled
                    $0.minimumHeight = value
                }
            }
            qualityLimit
            fileLimit
        }
    }

    private var qualityLimit: some View {
        HStack(spacing: 8) {
            Toggle(limits.minimumQuality, isOn: Binding(
                get: { presenter.policy.minimumQualityEnabled },
                set: { on in presenter.editPolicy { $0.minimumQualityEnabled = on } }
            ))
            .disabled(presenter.isWorking)
            TextField("%", value: Binding(
                get: { presenter.policy.minimumQualityPercent },
                set: { value in presenter.editPolicy { $0.minimumQualityPercent = value } }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 56)
            .disabled(presenter.isWorking || !presenter.policy.minimumQualityEnabled)
            Text("%")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var fileLimit: some View {
        HStack(spacing: 8) {
            Toggle(limits.minimumFileSize, isOn: Binding(
                get: { presenter.policy.minimumFileSizeEnabled },
                set: { on in presenter.editPolicy { $0.minimumFileSizeEnabled = on } }
            ))
            .disabled(presenter.isWorking)
            TextField(presenter.policy.minimumFileSizeUnit.label, value: Binding(
                get: { presenter.policy.minimumFileSizeValue },
                set: { value in presenter.editPolicy { $0.minimumFileSizeValue = value } }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .disabled(presenter.isWorking || !presenter.policy.minimumFileSizeEnabled)
            Picker(limits.minimumFileSize, selection: Binding(
                get: { presenter.policy.minimumFileSizeUnit },
                set: { unit in
                    presenter.editPolicy { policy in
                        let bytes = policy.minimumFileSizeUnit.bytes(from: policy.minimumFileSizeValue)
                        policy.minimumFileSizeUnit = unit
                        policy.minimumFileSizeValue = unit.amount(forBytes: bytes)
                    }
                }
            )) {
                ForEach(ShelfFitByteUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 72)
            .disabled(presenter.isWorking || !presenter.policy.minimumFileSizeEnabled)
            Spacer(minLength: 0)
        }
    }

    private func pixelLimit(title: String,
                            enabled: Bool,
                            value: Int,
                            commit: @escaping (Bool, Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: Binding(
                get: { enabled },
                set: { commit($0, value) }
            ))
            .disabled(presenter.isWorking)
            TextField(limits.pixels, value: Binding(
                get: { value },
                set: { commit(enabled, $0) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
            .disabled(presenter.isWorking || !enabled)
            Text(limits.pixels)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            if case .finished = presenter.phase {
                Button(strings.done) { presenter.close() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(strings.cancel) { presenter.close() }
                    .keyboardShortcut(.cancelAction)
                Button(strings.compress) { presenter.compress() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presenter.isWorking)
            }
        }
        .controlSize(.regular)
    }
}

/// A small note of each compressed file. It fades in, stays two seconds, and
/// goes away on its own. It does not take the keyboard or the pointer.
enum ShelfFitResultDialog {
    private static var panel: NSPanel?
    private static var dismissWork: DispatchWorkItem?
    private static var generation = 0
    /// Long enough for a capture name, its old size, and its new size on one line.
    private static let lineWidth: CGFloat = 560

    static func show(_ lines: [String]) {
        let lines = lines.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(lines) }
            return
        }
        let content = VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: lineWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let panel = ensurePanel()
        panel.contentViewController = host
        let frame = NSScreen.pointerVisibleFrame
        let width = min(size.width, frame.width - 32)
        let height = min(size.height, frame.height - 48)
        panel.setFrame(NSRect(x: frame.midX - width / 2,
                              y: frame.maxY - height - 24,
                              width: width,
                              height: height),
                       display: true)
        generation += 1
        let shown = generation
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss(shown) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private static func dismiss(_ shown: Int) {
        guard let panel, generation == shown else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard generation == shown else { return }
            panel.orderOut(nil)
            panel.contentViewController = nil
            dismissWork = nil
        })
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }
}
