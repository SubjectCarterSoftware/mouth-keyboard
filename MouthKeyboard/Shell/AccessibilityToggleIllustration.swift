import AppKit
import SwiftUI

/// An animated, in-app mock of the System Settings → Accessibility list row for
/// this app, with the toggle looping from off to green-on. It shows a
/// non-technical user exactly what to find and flip, without shipping a real
/// screenshot/GIF that would go stale across macOS releases.
struct AccessibilityToggleIllustration: View {
    @State private var isOn = false

    private var appIcon: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage(size: NSSize(width: 28, height: 28))
    }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            placeholderRow(width: 120)
            Divider().opacity(0.08)
            appRow
            Divider().opacity(0.08)
            placeholderRow(width: 90)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isOn = true
            }
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Privacy & Security › Accessibility")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var appRow: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)

            Text("Mouth Keyboard")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            miniToggle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
        )
    }

    private var miniToggle: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.green : Color.gray.opacity(0.55))
                .frame(width: 42, height: 26)

            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .padding(2)
                .overlay(
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                        .offset(x: 9, y: 9)
                        .opacity(isOn ? 0 : 1)
                )
        }
        .frame(width: 42, height: 26)
    }

    private func placeholderRow(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: 26, height: 26)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: width, height: 9)
            Spacer()
            Capsule()
                .fill(Color.white.opacity(0.07))
                .frame(width: 42, height: 26)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
