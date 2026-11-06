# Capture preparation input v1

Normative JSON is UTF-8 and schema-conformant. Required nullable facts use explicit JSON `null`; additive optional location fields are omitted when they do not apply so previously frozen v1 requests remain byte-valid. Unknown fields and enum values fail with a typed code and safe JSON path. UUID/SHA strings are lowercase. Integers use JSON decimal notation and the schema bounds. Arrays preserve order and are bounded by the schema.

The request freezes source/timezone/calendar/locale, operation and all core/renderer/profile pins, ordered discriminated text/link/asset payloads, complete preset/destination/route/metadata/location policy, and invocation/location outcome. A successful foreground location is represented by bounded integer microdegrees and optional millimetre accuracy; an unavailable attempt freezes its attempt time and typed reason. Optional label facts freeze whether lookup was requested, the `none`/`offline`/`systemMayUseNetwork` class, the disclosed consent version, a frozen/unavailable result, and nullable place/city/region/country values. City precision cannot retain an exact place. Structured location output freezes ordered field/output-key pairs so retries preserve selection and renaming exactly; materialization and retry never perform lookup. Each payload variant admits exactly its own fields. Logical paths are relative segment arrays. Storage handles, provider IDs, bookmarks, URIs, template bytes, and existing-note bytes are forbidden. Retry marker policy preserves `<!-- vox-capture:<lowercase-uuid> -->` semantics.

## Optional transcript property (November 2026)

`preset.metadataPolicy.transcriptProperty`, when present, contains `name` (1–128
alphanumeric/underscore/hyphen characters) and `value` (0–65,536 characters).
The native host freezes the processed voice transcript here and independently
chooses whether to include that transcript in the text payload. An empty text
payload is valid when this property is present. The property always applies to
document frontmatter, including when ordinary metadata uses entry scope. It
replaces the previous scalar or multiline value; other frontmatter and existing
body content are preserved. Values render as JSON-quoted YAML strings, never
interpreted YAML. The property participates in the canonical preset hash and
preparation snapshot; it is omitted entirely for historical/text-only captures.
Native vault identifiers remain opaque `destinationPolicy.capabilityReference`
values; native URIs and URL delivery credentials never cross this contract.
