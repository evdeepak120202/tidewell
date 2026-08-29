# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.1] — 2026-08-29

First beta. The engine and its guarantees are complete and tested; the surface around
them is where feedback is wanted.

### Added
- First-run setup wizard: four screens, ending in a real preview of your own files.
- Six organising styles, including **Caretaker**, which files nothing and only sets aside
  duplicates and archives stale files.
- Name rules — filename globs checked before file type, ordered, first match wins.
- Byte-identical duplicate detection (SHA-256, size pre-filtered), quarantined rather than
  deleted.
- Archive sweep into `Archive/YYYY-MM` for files untouched past a chosen age.
- Insights: what was filed, what is piling up, and one-click suggestions.
- Menu bar: today's summary, undo-all-today, and per-folder state.

- On-device document classification (macOS 26, Apple silicon), **off by default**, per
  folder, with a closed label set the model cannot escape, hard timeouts, thermal and
  low-power backoff, a content-hash cache, and full purge on disable.
- Five Shortcuts actions via App Intents, including the SwiftPM build steps needed to
  produce App Intents metadata without an Xcode project.
- Insights tab: weekly activity, category breakdown, and suggestions that write real rules.

### Fixed
- Files held back by the arrival delay were never re-checked and could sit indefinitely,
  because a file's arrival is the only filesystem event it generates. A deferred file now
  books its own follow-up pass.
- Adding a field to a persisted type made every existing settings file undecodable, and
  `load()` swallowed the error — the app started with no watched folders and would have
  overwritten the real config on the next save. Decoders now migrate, and a failed load
  refuses to save over the original.

### Known limitations

- **Not notarised.** Notarisation requires a paid Apple Developer membership this project
  does not have, so a downloaded build shows a Gatekeeper warning. `brew install` compiles
  locally and has no warning — see the README.
- **No App Sandbox yet.** Planned; it needs security-scoped bookmarks retrofitted onto the
  folder watcher, which deserves its own careful pass rather than being rushed for a beta.
- **English only.** The package declares a default localisation so translation is a PR.
- On-device reading needs macOS 26 on Apple silicon. Everything else works without it.
