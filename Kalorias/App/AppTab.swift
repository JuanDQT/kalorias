//
//  AppTab.swift
//  Kalorias
//
//  The two selectable content destinations in the bottom bar. The center
//  camera is an action, not a member of this enum (see Router / BottomBar).
//

import Foundation

nonisolated enum AppTab: Hashable, CaseIterable {
    case progress
    case history
}
