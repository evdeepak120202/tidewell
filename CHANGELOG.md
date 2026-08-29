# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.4] — 2026-08-29

### Added
- **A rules editor**, and an **App Sweep pane**. beta.3 shipped both engines with no way
  to reach either from the app — the rule engine could only be driven by hand-editing
  JSON inside the sandbox container, and App Sweep could not be reached at all. Rules now
  live in the folder pane with starters for the common cases; App Sweep is its own item in
  the sidebar.

### Changed
- The old filename-pattern list is renamed **Name patterns** and described as the simpler
  form of a rule, so the two are not confused.

## [0.1.0-beta.3] — 2026-08-29

### Added
- **App Sandbox.** Tidewell now runs confined: it can reach only the folders you have
  chosen, and the kernel enforces that rather than the code promising it. Access survives
  quitting through security-scoped bookmarks, and a bookmark that goes stale is re-minted
  and saved — one that resolves without being refreshed keeps working for a launch and
  then quietly stops.
- **Rules with conditions and actions.** Name, extension, kind, size, age and duplicate
  status, combined with all/any/none, evaluated before name patterns and before file type.
  First match wins. The action set is deliberately incapable of destruction: move, tag,
  colour label, leave alone, set aside for review — no delete, and no run-a-script.
- **App Sweep.** Point Tidewell at an app you have removed and it finds what it left in
  your Library, matched on bundle identifier only. It **gathers** them into a folder for
  you to look through rather than deleting them, because "probably belongs to that app"
  is a guess and a guess should not be able to destroy a licence file.

### Changed
- **Breaking: settings move into the sandbox container.** A confined app cannot read
  `~/Library/Application Support/Tidewell`, so existing watched folders are not carried
  over and setup runs again. Your files are untouched; only Tidewell's own configuration
  is affected. The old file is left where it was if you want to consult it.
- App Sweep needs one-time access to your Library folder, granted through a panel like any
  other folder. That is more friction than an unconfined competitor, and a much better
  guarantee about what the app can reach.

## [0.1.0-beta.2] — 2026-08-29

First beta. The engine and its guarantees are complete and tested; the surface around
them is where feedback is wanted.

> `0.1.0-beta.1` was withdrawn within minutes: `brew install` failed with
> `sandbox_apply: Operation not permitted` before compiling anything, because Homebrew
> builds inside its own sandbox and SwiftPM sandboxes manifest compilation with
> `sandbox-exec` — the two cannot nest. `Scripts/build.sh` now honours `SWIFT_FLAGS` and
> the formula passes `--disable-sandbox`. The formula also passes the version through, so
> the bundle no longer reports a version that was never released.

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
