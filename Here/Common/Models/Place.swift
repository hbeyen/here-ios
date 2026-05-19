import Foundation

/// One row out of the `public.places` Supabase table — the minimal slice the
/// Places list scene actually renders. Mirror more fields as later scenes
/// (per-place dashboard, edit, broadcast) need them.
///
/// See `Here-Audio/lib/places-server.ts` for the canonical zod schema and
/// `Here-Audio/docs/sql/002_places.sql` for the column definitions. Booleans
/// like `isActive` are server-defaulted (`not null default true`), so we
/// surface them as non-optional here.
///
/// Decoded by `APIClient.defaultDecoder()` which has
/// `keyDecodingStrategy = .convertFromSnakeCase`, so snake_case columns map
/// to camelCase properties without an explicit `CodingKeys` enum.
struct Place: Decodable, Identifiable, Equatable {
  let id: String
  let slug: String
  let name: String
  let tagline: String
  let accent: String
  let isActive: Bool
}
