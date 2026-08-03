//
//  BottomBar.swift
//  Kalorias
//
//  The shared bottom navigation bar. It is drawn with Apple's NATIVE Liquid
//  Glass (`GlassEffectContainer` + `.glassEffect` / the `.glassProminent`
//  button style) per constitution Principle III — never a hand-rolled
//  imitation. All color comes from the `AppColor` tokens.
//
//  Two selectable tabs (Progress, History) flank a prominent green Camera
//  action in the center. The camera is an action, not a content tab.
//

import SwiftUI

struct BottomBar: View {
    /// Vertical space a scrolling screen must reserve at its bottom so its last
    /// element can come to rest clear of this floating bar.
    ///
    /// ONE declaration on purpose. This value has already been duplicated once:
    /// feature 005 hardcoded it in the Progress tab, feature 006 deleted that and
    /// replaced it with a root-level safe-area inset that `NavigationStack` silently
    /// swallowed, leaving the details screen with no clearance at all. Owned by the
    /// bar because it describes the bar's own footprint (Principle I).
    ///
    /// Covers the 64pt camera button, the bar's 10pt vertical padding, its 8pt bottom
    /// offset, the home-indicator area a scroll view extends under, and breathing room.
    static let scrollClearance: CGFloat = 112

    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void
    let onCamera: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 0) {
                tabButton(.progress, systemImage: "chart.line.uptrend.xyaxis", title: "tab.progress")
                Spacer(minLength: 0)
                cameraButton
                Spacer(minLength: 0)
                tabButton(.history, systemImage: "clock.arrow.circlepath", title: "tab.history")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 24)
    }

    private func tabButton(_ tab: AppTab, systemImage: String, title: LocalizedStringKey) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: 72)
            .foregroundStyle(isSelected ? AppColor.brandPrimary : AppColor.textSecondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab == .progress ? "tab.progress" : "tab.history")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var cameraButton: some View {
        Button(action: onCamera) {
            // No explicit foreground color: `.glassProminent` derives a label
            // color that contrasts with its own tint. Forcing `.white` here
            // overrode that with a raw literal measuring 2.70:1 against the
            // brand fill. Principle III is explicit that accessibility
            // behaviour for translucency "is the system's job, not the app's".
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .bold))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glassProminent)
        .tint(AppColor.brandPrimaryFill)
        .clipShape(.circle)
        .accessibilityIdentifier("bottomBar.cameraButton")
        .accessibilityLabel(Text("camera.capture"))
    }
}

#Preview {
    ZStack {
        AppColor.surfacePrimary.ignoresSafeArea()
        VStack {
            Spacer()
            BottomBar(selectedTab: .progress, onSelect: { _ in }, onCamera: {})
        }
    }
}
