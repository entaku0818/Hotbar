import SwiftUI
import AppKit

struct OverlayView: View {
    @EnvironmentObject var store: HotbarStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var slotAssigned: Int?
    @State private var isAccessibilityGranted = AXIsProcessTrusted()

    private var closeHint: String {
        settings.holdMode
            ? L10n.text("Release modifier to switch · ESC to cancel")
            : L10n.format("%@ or ESC to close", HotkeyPreference.load().displayString)
    }

    var body: some View {
        GeometryReader { geometry in
            overlayContent(width: geometry.size.width)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(.secondary)
            Text("Hotbar")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(closeHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func overlayContent(width: CGFloat) -> some View {
        ZStack {
            // Background blur
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )

            VStack(spacing: 16) {
                header

                // Window grid (upper section) — listing works without any permission
                WindowGridView(
                    windows: store.windows,
                    selectedIndex: $store.selectedIndex,
                    sizeScale: min(1.5, max(0.8, width / 900))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                WindowActionBar()
                    .padding(.horizontal, 20)

                // Non-blocking hint when accessibility is missing
                if !isAccessibilityGranted {
                    AccessibilityHintBanner()
                        .padding(.horizontal, 20)
                }

                Divider()
                    .padding(.horizontal, 20)

                // Hotbar (lower section)
                HotbarSlotRow(slots: store.slots, assignedSlot: slotAssigned)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted != isAccessibilityGranted {
                isAccessibilityGranted = trusted
                if trusted {
                    store.refreshWindows()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotbarSlotAssigned)) { notification in
            if let digit = notification.object as? Int {
                withAnimation(.spring(response: 0.3)) {
                    slotAssigned = digit
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    slotAssigned = nil
                }
            }
        }
    }
}

// MARK: - Window grid

struct WindowGridView: View {
    let windows: [WindowInfo]
    @Binding var selectedIndex: Int
    var sizeScale: CGFloat
    @ObservedObject private var settings = AppSettings.shared

    private var cellWidth: CGFloat { settings.thumbnailSize * sizeScale }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 40), spacing: 12)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if windows.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.on.rectangle.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No windows found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    grid
                }
            }
            .coordinateSpace(name: Self.gridSpace)
            .onPreferenceChange(CellFramesKey.self) { HotbarStore.shared.cellFrames = $0 }
            .onChange(of: selectedIndex) { index in
                guard windows.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(windows[index].id) }
            }
        }
    }

    private static let gridSpace = "windowGrid"

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                WindowCell(
                    window: window,
                    isSelected: selectedIndex == index,
                    previewHeight: cellWidth * 0.68
                )
                .id(window.id)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CellFramesKey.self,
                                           value: [index: geometry.frame(in: .named(Self.gridSpace))])
                })
                .onTapGesture {
                    selectedIndex = index
                    // Hide overlay first so it doesn't steal focus
                    NotificationCenter.default.post(name: .hideOverlay, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        HotbarStore.shared.activateWindow(window)
                    }
                }
                .onContinuousHover { phase in
                    // Only an actual pointer move selects; a cursor resting where the
                    // switcher opens must not override the default (previous) window.
                    if case .active = phase, selectedIndex != index, HotbarStore.shared.pointerHasMoved() {
                        selectedIndex = index
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Window cell

struct WindowCell: View {
    let window: WindowInfo
    let isSelected: Bool
    let previewHeight: CGFloat
    @ObservedObject private var settings = AppSettings.shared

    private var accent: Color { settings.accent.color }
    /// Without Screen Recording the title falls back to the app name — don't print it twice.
    private var hasDistinctTitle: Bool { settings.showTitles && window.title != window.appName }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? accent.opacity(0.3) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? accent : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 4 : 1
                            )
                    )
                    .shadow(color: isSelected ? accent.opacity(0.8) : .clear, radius: isSelected ? 18 : 0)

                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if window.thumbnail != nil, let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: isSelected ? 30 : 24, height: isSelected ? 30 : 24)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .offset(x: -6, y: 6)
                }
            }
            .frame(height: previewHeight)

            nameplate
        }
        .contentShape(Rectangle())
        // Dim the rest so the switch target stands out at a glance.
        .opacity(isSelected ? 1.0 : 0.5)
        .saturation(isSelected ? 1.0 : 0.5)
        .scaleEffect(isSelected ? 1.08 : 0.96)
        .zIndex(isSelected ? 1 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
    }

    private var nameplate: some View {
        VStack(spacing: 2) {
            Text(hasDistinctTitle ? window.title : window.appName)
                .font(.system(size: isSelected ? 14 : 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if hasDistinctTitle {
                Text(window.appName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isSelected ? 6 : 3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent : Color.clear)
                .shadow(color: isSelected ? accent.opacity(0.5) : .clear, radius: 6, y: 2)
        )
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail = window.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(isSelected ? 8 : 6)
        } else if let icon = window.appIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: isSelected ? 64 : 48, height: isSelected ? 64 : 48)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Accessibility prompt

struct AccessibilityHintBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Accessibility is off — hotkeys and per-window switching may not work.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: - Hotbar slot row

struct HotbarSlotRow: View {
    @EnvironmentObject var store: HotbarStore
    let slots: [Int: WindowInfo]
    let assignedSlot: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...9, id: \.self) { index in
                HotbarSlot(
                    index: index,
                    window: slots[index],
                    isJustAssigned: assignedSlot == index
                )
                .onTapGesture {
                    guard slots[index] != nil else { return }
                    NotificationCenter.default.post(name: .hideOverlay, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { store.activateSlot(index: index) }
                }
                .help(slots[index]?.title ?? L10n.format("Hold %d to assign the selected window", index))
            }
        }
    }
}

// MARK: - Individual hotbar slot

struct HotbarSlot: View {
    let index: Int
    let window: WindowInfo?
    let isJustAssigned: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(window != nil
                        ? settings.accent.color.opacity(0.15)
                        : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isJustAssigned ? Color.yellow :
                                    (window != nil ? settings.accent.color.opacity(0.5) : Color.white.opacity(0.1)),
                                lineWidth: isJustAssigned ? 2 : 1
                            )
                    )
                    .scaleEffect(isJustAssigned ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isJustAssigned)

                if let icon = window?.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                } else if window != nil {
                    Image(systemName: "app.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                } else {
                    Text("+")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 56, height: 56)

            if settings.showSlotNames {
                Text(window?.appName ?? L10n.text("Empty"))
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 2) {
                Image(systemName: "command")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text("\(index)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
