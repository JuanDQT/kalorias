//
//  OnboardingServerStatus.swift
//  Kalorias
//
//  What the backend says about this account's onboarding: it still needs one, or
//  it already has one (feature 010, FR-021).
//
//  THE SERVER OWNS THIS ANSWER, NOT THE DEVICE. A local "I finished the
//  questions" flag says the user typed the last answer; it says nothing about
//  whether a plan exists. Those are different facts, and conflating them is how
//  a returning user's existing plan gets overwritten by answers they re-entered
//  on a new phone.
//
//  UNKNOWN VALUES FAIL DECODING. `unknown` mapped to a default is the shape of
//  bug that lets a future server status the app has never heard of be treated as
//  "complete", which opens the app with no plan behind it. Refusing the whole
//  response is the safe direction: it keeps the user on a screen with a retry.
//

import Foundation

nonisolated enum OnboardingServerStatus: String, Codable, Sendable, Equatable {
    /// The account exists but has no plan yet. The sealed local answers are
    /// still needed.
    case required
    /// The account already has a plan. Local pending answers are redundant and
    /// must never be uploaded over it (FR-022).
    case complete
}
