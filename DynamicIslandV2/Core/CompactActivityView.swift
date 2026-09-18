import SwiftUI

struct CompactActivityView: View {
    let activity: CompactActivity
    let sideWidth: CGFloat
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch activity.style {
        case .success: return .green
        case .failure: return .orange
        case .notice: return .cyan
        case .working, .countdown: return .white
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: sideWidth)
                Spacer(minLength: 0)
                Group {
                    if activity.style == .working {
                        if reduceMotion {
                            Image(systemName: "ellipsis")
                        } else {
                            ProgressView().controlSize(.mini).tint(color)
                        }
                    } else {
                        Text(activity.label)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: sideWidth)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(activity.detail)
        .accessibilityLabel(activity.detail)
        .accessibilityHint("Apri i dettagli dell’attività")
    }
}
