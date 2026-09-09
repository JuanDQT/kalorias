//
//  AppJourneyPhase.swift
//  Kalorias
//
//  What the root of the app is showing, and the only thing it consults to decide
//  (feature 010, FR-027).
//
//  IT REPLACES A BOOLEAN, AND THE BOOLEAN WAS THE BUG. `onboarding.completed`
//  could answer exactly one question — "has this device finished the chat?" —
//  and the new flow has five that are all different: the answers are sealed but
//  there is no account; there is an account but no consent; there is consent but
//  the upload has not been confirmed; the account exists on the server but this
//  device has no live session; a deletion the user confirmed is still
//  outstanding. Any two of those collapsed into one flag produce either a user
//  stuck outside their own app or, worse, an authenticated screen over an
//  account that no longer exists.
//
//  EXACTLY ONE PHASE IS ON SCREEN. These are not layers: `RootView` switches,
//  it does not present access *over* a running tab shell. An authenticated view
//  must not be built, let alone render, behind an identity gate — not even for
//  the length of an animation.
//
//  THE ORDER IS DECIDED AT BOOTSTRAP, NOT ACCUMULATED. `AppJourneyStore`
//  resolves the phase from durable state (Keychain, protected files) in one
//  deterministic pass, so a relaunch lands where the last process left off
//  rather than replaying a sequence of transitions.
//

import Foundation

nonisolated enum AppJourneyPhase: Equatable, Sendable {

    /// Reading Keychain and protected storage. Also where a locked device waits:
    /// "cannot read yet" is not "there is nothing there".
    case restoring

    /// The questionnaire, answered locally.
    case onboarding

    /// Sign in with Apple. Reached with a sealed payload behind it, or by a
    /// known account whose session has gone.
    case access

    /// Registered, with answers waiting and no consent yet.
    case consent

    /// Registered and consented; the sealed payload is being — or waiting to be
    /// — submitted.
    case finalizing

    /// An authenticated account whose server onboarding is complete. The only
    /// phase in which the tab shell exists.
    case ready

    /// A deletion the user confirmed is outstanding. Authenticated content stays
    /// hidden until it resolves, because the account may already be gone.
    case deletingAccount

    /// Whether the authenticated app shell may be built at all.
    var showsAuthenticatedShell: Bool { self == .ready }
}

/// A local-storage problem the user has to be told about, surfaced by the root
/// rather than swallowed.
///
/// Corrupt protected data is never silently deleted and never sent: both are
/// ways to lose or leak answers without anyone deciding to.
nonisolated enum JourneyLocalDataError: Equatable, Sendable {
    case corruptedOnboardingData
    case unreadableCredentials
}
