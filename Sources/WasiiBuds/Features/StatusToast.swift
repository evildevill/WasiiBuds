import SwiftUI

struct StatusToastPresenter: ViewModifier {
    @ObservedObject var explorer: BluetoothExplorer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let notice = explorer.notice {
                HStack(spacing: 12) {
                    if notice.kind == .progress {
                        ProgressView().tint(Studio.accent)
                    } else {
                        Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(Studio.accent)
                    }
                    Text(notice.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Studio.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .frame(minHeight: 54)
                .background(Studio.background, in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Studio.line, lineWidth: 1))
                .overlay(alignment: .leading) {
                    Capsule().fill(Studio.accent).frame(width: 3, height: 23)
                        .padding(.leading, 5)
                }
                .shadow(color: Studio.primary.opacity(0.11), radius: 16, y: 6)
                .frame(maxWidth: 340)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in dragOffset = min(0, value.translation.height) }
                        .onEnded { value in
                            if value.translation.height < -28 {
                                explorer.dismissNotice()
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .accessibilityAction(named: "Dismiss notification") { explorer.dismissNotice() }
                .id(notice.id)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                   value: explorer.notice?.id)
        .onChange(of: explorer.notice?.id) { _, _ in dragOffset = 0 }
    }
}
