# Task 005: Decode + surface Supabase auth error responses (hotfix)

**Status**: OPEN — **BLOCKING DEVICE TESTING**
**Owner**: Fresh Claude Code session
**Created**: 2026-05-19
**Priority**: Highest — sign-in is broken end-to-end

## Goal

When `SupabaseAuthClient.signInWithApple` gets a non-success response from `/auth/v1/token?grant_type=id_token`, surface the actual Supabase error message instead of the misleading "Could not parse response: The data couldn't be read because it is missing." The user can then act on the real cause; the conductor can dispatch the right next fix.

## Context

Reproduced on iPhone 17 Pro (2026-05-19): tap Sign in with Apple → Face ID → app shows the parse-error message above. The actual auth-server response is being eaten by a `DecodingError` because:

- [`Here/Common/Auth/SupabaseAuthClient.swift`](../../Here/Common/Auth/SupabaseAuthClient.swift)'s `Session` struct declares `accessToken: String` and `refreshToken: String` as non-optional
- If Supabase returns an error JSON like `{ "error": "invalid_grant", "error_description": "..." }` or `{ "msg": "..." }` or `{ "error_code": "..." }`, neither `access_token` nor `refresh_token` is present
- The decoder fails with `keyNotFound`, which Foundation renders as "data couldn't be read because it is missing"
- The error displayed gives no hint about the real cause (could be wrong audience claim, mis-configured provider, nonce mismatch, network issue — we have no idea)

The web Capacitor app worked end-to-end with the same Supabase Apple provider config + same bundle ID `fm.here.app`. So the provider config itself is probably fine; the bug is most likely in how the native client is constructing the request OR in how it handles non-success responses.

## Steps

1. **Inspect status code + raw body before decoding.** In [`Here/Common/Networking/APIClient.swift`](../../Here/Common/Networking/APIClient.swift)'s `send(_:expecting:)` (or wherever the URLSession call lives), branch on the HTTP status:
   - 2xx → decode `expecting` as today
   - 4xx / 5xx → attempt to decode a small error envelope (try multiple shapes — see below), throw a meaningful `APIError`
   - Always capture the raw body as a `String?` and include the first ~200 chars in the thrown error's message so we can see exactly what Supabase said

2. **Error envelope shapes to try** (in order of probability for Supabase Auth):
   ```swift
   struct SupabaseAuthError: Decodable {
     let error: String?           // e.g. "invalid_grant"
     let errorDescription: String?  // e.g. "Apple Id Token verification failed"
     let errorCode: String?
     let msg: String?              // some legacy paths use msg
     let code: Int?

     enum CodingKeys: String, CodingKey {
       case error
       case errorDescription = "error_description"
       case errorCode = "error_code"
       case msg
       case code
     }
   }
   ```
   Construct the thrown error's message from whichever of `errorDescription`, `error`, `msg` is non-nil. Include the HTTP status in the message ("HTTP 400: invalid_grant — Apple Id Token verification failed").

3. **Surface in the UI**: `SignInViewModel` already renders the thrown error via `error` state. Confirm the new richer message shows up on screen.

4. **Reproduce on simulator** to verify the better error message appears. Sign in with Apple, observe the new banner. If the underlying cause is now visible (e.g. "invalid_grant: Apple Id Token verification failed — wrong audience claim"), document it in the PR body so the conductor can dispatch the next fix.

5. **If the diagnosed cause is a one-line fix in here-ios** (e.g. wrong field name, missing header, audience claim issue), apply it in the same PR — but don't speculate. Only ship a fix if reproduction confirms it. Otherwise leave it for the next task.

6. **`pnpm verify`-equivalent**: `xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build` must stay clean.

7. **Commit + push** on `claude/auth-error-decoding`. Open PR titled `fix(auth): decode + surface Supabase auth error responses (hotfix)`.

## Acceptance

- Build clean
- When Supabase returns a non-success status, the error banner shows the actual Supabase error message (or at minimum the HTTP status + first chunk of body)
- The "Could not parse response: The data couldn't be read because it is missing." surface is gone for auth failures
- PR body documents what the real error from Supabase is (the implementer must reproduce on simulator and screenshot/transcribe the new error message)

## Out of scope

- Any UI redesign for the sign-in error banner
- Refresh-token rotation hardening
- Logging frameworks / telemetry — `print()` to stdout for now if needed for debugging, but don't ship a logger
- Anything in Here-Audio

## How to report back

Same format. PR URL, files changed, **the actual Supabase error you saw on simulator** (this is critical — the next task depends on knowing it), any design choices.
