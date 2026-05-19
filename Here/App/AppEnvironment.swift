import Foundation

/// Build-time configuration. Reads from `Info.plist` first (so the same
/// binary can flip between Dev / Prod via xcconfig), falling back to
/// hard-coded production values so the app runs out of the box on a
/// fresh checkout without any extra setup.
///
/// `supabaseAnonKey` is *public* by Supabase's design (RLS enforces auth on
/// every read), but we still don't commit it to the repo — drop it into a
/// local `.xcconfig`, into the scheme's environment variables, or directly
/// into `Info.plist` (`HERE_SUPABASE_ANON_KEY`) for development. Production
/// builds get it from the Workers Builds env at archive time.
struct AppEnvironment {
  enum Build {
    case debug
    case release
  }

  let build: Build
  let workerBaseURL: URL
  let supabaseURL: URL
  let supabaseAnonKey: String

  static let production = AppEnvironment(
    build: detectBuild(),
    workerBaseURL: URL(string: "https://here-audio.henock-23c.workers.dev")!,
    supabaseURL: URL(string: "https://xiqyaryjagujgsxcuabb.supabase.co")!,
    supabaseAnonKey: infoPlistString("HERE_SUPABASE_ANON_KEY") ?? ""
  )

  private static func detectBuild() -> Build {
    #if DEBUG
    return .debug
    #else
    return .release
    #endif
  }

  private static func infoPlistString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty else {
      return nil
    }
    return value
  }
}
