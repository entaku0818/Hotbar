import SwiftUI
import AppKit

struct OverlayView: View {
    @EnvironmentObject var store: HotbarStore
    @State private var slotAssigned: Int? = nil

    var body: some View {
        ZStack {
            // Background blur
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )

            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(.secondary)
                    Text("Hotbar")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("ESC to close")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Window grid (upper section)
                WindowGridView(windows: store.windows, selectedIndex: $store.selectedIndex)
                    .frame(maxHeight: 380)

                Divider()
                    .padding(.horizontal, 20)

                // Hotbar (lower section)
                HotbarSlotRow(slots: store.slots, assignedSlot: slotAssigned)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 900, height: 560)
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

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
    ]

    var body: some View {
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
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        WindowCell(
                            window: window,
                            isSelected: selectedIndex == index
                        )
                        .onTapGesture {
                            selectedIndex = index
                            HotbarStore.shared.activateWindow(window)
                            NotificationCenter.default.post(name: .hideOverlay, object: nil)
                        }
                        .onHover { hovering in
                            if hovering {
                                selectedIndex = index
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Window cell

struct WindowCell: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                if let thumbnail = window.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(6)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 110)

            VStack(spacing: 2) {
                Text(window.appName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(window.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

// MARK: - Hotbar slot row

struct HotbarSlotRow: View {
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
            }
        }
    }
}

// MARK: - Individual hotbar slot

struct HotbarSlot: View {
    let index: Int
    let window: WindowInfo?
    let isJustAssigned: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(window != nil
                        ? Color.accentColor.opacity(0.15)
                        : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isJustAssigned ? Color.yellow : (window != nil ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1)),
                                lineWidth: isJustAssigned ? 2 : 1
                            )
                    )
                    .scaleEffect(isJustAssigned ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isJustAssigned)

                if let icon = window?.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
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
