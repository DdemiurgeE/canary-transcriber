import SwiftUI
import AppKit

/// A log panel with a drag-to-resize handle, shared by the Library's always-available
/// Logs button and the per-session log drawer.
struct ResizableLogPanel: View {
    @Binding var height: CGFloat
    let text: String

    @State private var heightAtDragStart: CGFloat?
    @State private var isResizeCursorPushed = false

    var body: some View {
        VStack(spacing: 0) {
            handle
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var handle: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 6)
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 32, height: 3)
        }
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                pushResizeCursor()
            } else if heightAtDragStart == nil {
                popResizeCursor()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if heightAtDragStart == nil {
                        heightAtDragStart = height
                        pushResizeCursor()
                    }
                    let proposed = (heightAtDragStart ?? height) - value.translation.height
                    height = min(max(proposed, 80), 500)
                }
                .onEnded { _ in
                    heightAtDragStart = nil
                    popResizeCursor()
                }
        )
    }

    private func pushResizeCursor() {
        guard !isResizeCursorPushed else { return }
        isResizeCursorPushed = true
        NSCursor.resizeUpDown.push()
    }

    private func popResizeCursor() {
        guard isResizeCursorPushed else { return }
        isResizeCursorPushed = false
        NSCursor.pop()
    }
}
