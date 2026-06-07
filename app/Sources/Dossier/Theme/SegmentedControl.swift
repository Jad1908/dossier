import SwiftUI

// DESIGN.md §segmented-control — the inline-body / saved-prompt toggle and the
// preview's Outline / Full-prompt toggle. Track on surface-elevated; the active
// segment lifts to surface-card (dark) / surface (light) with ink text.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isActive = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(Theme.Typography.bodyStrong)
                        .foregroundStyle(isActive ? Theme.Colors.ink : Theme.Colors.mute)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity)
                        .background(
                            isActive ? Theme.Colors.surfaceCard : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm,
                                                 style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
