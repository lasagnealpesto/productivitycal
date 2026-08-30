//
//  SupabaseSync.swift
//
//  Bridges the app's existing native Sign in with Apple / Google Sign-In to a
//  real Supabase account, and keeps each day's mood synced to a `moods` table
//  so history survives a reinstall or following the account to a new device
//  (today it only lives in this device's local App Group storage).
//
//  SETUP (in Xcode, ~2 minutes) — this file won't compile in until you do this:
//  1. File > Add Package Dependencies... > paste:
//     https://github.com/supabase/supabase-swift
//  2. Pick a version rule (e.g. "Up to Next Major") and add it to the "endar"
//     app target, selecting the "Supabase" library product.
//  3. Build. Everything below is gated behind `#if canImport(Supabase)`, so
//     the app already builds and runs fine without this — the sync feature
//     just stays inactive until the package is added.
//
//  Backend: a Supabase project named "productivitycal" already exists (see
//  BACKLOG.md) with a `moods` table (user_id, day, mood, updated_at) and row
//  level security scoped to auth.uid(), so each account only ever sees its
//  own rows.
//

import Foundation

#if canImport(Supabase)
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://nxcdjnmiulliwpwnbbsx.supabase.co")!
    // Public/publishable key — safe to embed client-side, all access is
    // gated by the table's row-level-security policies, not this key.
    static let publishableKey = "sb_publishable_W-IFOHPODGetCLgc7d4I5A_nZL4hNxy"
}

enum MoodSyncProvider {
    case apple
    case google
}

enum MoodSyncService {
    static let client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.publishableKey)

    private struct MoodRow: Codable {
        let day: String
        let mood: String
    }

    private struct MoodUpsertRow: Codable {
        let user_id: String
        let day: String
        let mood: String
    }

    /// Exchanges a native Sign in with Apple / Google ID token for a real
    /// Supabase session. Safe to call on every interactive sign-in — the
    /// Supabase SDK itself persists and auto-refreshes the resulting session
    /// across app launches, so this does NOT need to be repeated on a silent
    /// session restore.
    static func signIn(idToken: String, provider: MoodSyncProvider) async {
        do {
            let supaProvider: OpenIDConnectCredentials.Provider = provider == .apple ? .apple : .google
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: supaProvider, idToken: idToken)
            )
        } catch {
            // Non-fatal: the app keeps working fully offline/local if this
            // fails (no network, misconfigured provider, etc.) — sync just
            // sits out until the next successful sign-in or launch.
        }
    }

    static func signOut() async {
        try? await client.auth.signOut()
    }

    /// The signed-in account's email, for display in the profile menu. `nil`
    /// if there's no session yet (offline, not signed in) or the provider
    /// didn't share one.
    static func currentUserEmail() async -> String? {
        guard let session = try? await client.auth.session else { return nil }
        return session.user.email
    }

    private struct FeedbackInsertRow: Codable {
        let user_id: String
        let email: String?
        let message: String
        let app_version: String
        let platform: String
    }

    /// Inserts a row into `feedback`; a Supabase Database Webhook on that
    /// table turns each insert into a GitHub issue on the repo, so app
    /// feedback lands directly in the project's to-do list.
    static func submitFeedback(message: String, appVersion: String) async throws {
        let session = try await client.auth.session
        let row = FeedbackInsertRow(
            user_id: session.user.id.uuidString,
            email: session.user.email,
            message: message,
            app_version: appVersion,
            platform: "ios"
        )
        _ = try await client
            .from("feedback")
            .insert(row)
            .execute()
    }

    /// Plain email + password account, as an alternative to Apple/Google —
    /// also what an App Store reviewer can use without a real Apple/Google
    /// account (see BACKLOG.md for the demo account's credentials).
    static func signInWithPassword(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    static func signUpWithPassword(email: String, password: String) async throws {
        _ = try await client.auth.signUp(email: email, password: password)
    }

    /// Pulls the signed-in user's full remote history, fills any local gaps
    /// with it (local wins on conflicts, see `MoodStore.mergeRemote`), then
    /// pushes the merged result back up so both sides end up equal. Call
    /// once when the main app screen appears, signed in or not — it no-ops
    /// without a session.
    @MainActor
    static func syncNow(store: MoodStore) async {
        do {
            let userID = try await client.auth.session.user.id

            let rows: [MoodRow] = try await client
                .from("moods")
                .select("day, mood")
                .execute()
                .value

            var remoteMoods: [String: Mood] = [:]
            for row in rows {
                if let mood = Mood.fromStoredValue(row.mood) {
                    remoteMoods[row.day] = mood
                }
            }
            store.mergeRemote(remoteMoods)

            let merged = store.moods
            guard !merged.isEmpty else { return }
            let payload = merged.map { day, mood in
                MoodUpsertRow(user_id: userID.uuidString, day: day, mood: mood.rawValue)
            }
            _ = try await client
                .from("moods")
                .upsert(payload, onConflict: "user_id,day")
                .execute()
        } catch {
            // Not signed in yet, offline, or a transient API error — local
            // storage remains the source of truth either way.
        }
    }

    /// Pushes a single day's change right away (fire-and-forget), so data
    /// isn't only backed up at the next full sync. No-ops silently if
    /// there's no Supabase session yet.
    static func pushSingleDay(_ day: String, mood: Mood?) {
        Task {
            do {
                let userID = try await client.auth.session.user.id
                if let mood {
                    _ = try await client
                        .from("moods")
                        .upsert(
                            MoodUpsertRow(user_id: userID.uuidString, day: day, mood: mood.rawValue),
                            onConflict: "user_id,day"
                        )
                        .execute()
                } else {
                    _ = try await client
                        .from("moods")
                        .delete()
                        .eq("user_id", value: userID.uuidString)
                        .eq("day", value: day)
                        .execute()
                }
            } catch {
                // Best-effort; local storage is unaffected either way, and
                // the next full `syncNow` reconciles anything missed.
            }
        }
    }
}
#endif
