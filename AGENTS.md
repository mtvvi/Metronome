# AGENTS.md

## Project

iOS Swift music player with local files, user-selected Files folders, media
library import, gapless playback, parametric EQ, and high-resolution audio
output diagnostics.

## Local Context

- Before substantial work, check `.codex/context/` and `.codex/plans/` if they
  exist. These files contain local-only project memory for future Codex chats.
- Never commit `.codex/`, `.codex-log/`, local planning files, copied
  recommendation files, or private backlog notes.
- Public GitHub content should contain only real project files and stable
  project guidance. Keep detailed planning and recommendations local unless the
  user explicitly says otherwise.
- If local context is absent, continue from public project files and ask only
  when a decision cannot be recovered safely.

## Language and Style

- Use Swift 6 where possible.
- Use SwiftUI for UI.
- Use async/await and actors for scanning, database, and background work.
- Do not use force unwraps.
- Do not put business logic in SwiftUI views.
- Keep files below 400 lines when practical.
- Prefer small, testable types with clear protocol boundaries.

## Architecture

- AudioCore must not import SwiftUI.
- Persistence must not import SwiftUI.
- Features may import Core modules.
- UI must call services through protocols.
- Keep audio, persistence, scanning, DSP, and UI responsibilities separated.

## Audio Rules

- Never allocate, log, lock, call async functions, or touch the database from an
  audio render callback.
- All DSP configuration used by real-time audio code must be immutable
  snapshots.
- EQ, preamp, ReplayGain, limiter, and other DSP must be bypassed in
  bit-perfect mode.
- Always expose the actual `AVAudioSession` route and sample rate in
  diagnostics.
- Do not promise whole-phone scanning. Only index app-container files,
  user-selected folders, Music library items, and Files providers the user has
  explicitly granted access to.
- Do not promise guaranteed sample-rate switching on iOS. Request preferred
  values, then report actual values.

## Dependencies and Licensing

- Do not add GPL, nonfree, or unclear-license dependencies.
- Any new dependency must have an explicit project reason and license review.
  Keep detailed dependency notes local under `.codex/context/` unless the user
  asks for a public dependency ledger.
- Prefer GRDB for persistence.
- Prefer SFBAudioEngine for wide-format decoding unless a task says otherwise.
- Do not add FFmpegKit.
- Native SMB support is advanced scope and requires license review before any
  implementation.

## Testing

- Add or update tests for database migrations, scanner behavior, metadata
  parsing, EQ math, and queue logic when touching those areas.
- Run `xcodebuild test` before completing implementation tasks when working on
  macOS.
- On Windows, document that iOS build verification is unavailable if `swift`
  and `xcodebuild` are not installed.
