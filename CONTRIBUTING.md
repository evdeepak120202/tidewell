# Contributing to Tidewell

## Before anything else

Tidewell moves people's files. A bug here is not a cosmetic glitch — it is someone's tax
return in the wrong folder, or worse. Two rules follow from that and are not negotiable:

1. **Nothing in `TidewellCore` may delete, trash or overwrite.** `FileMover` is the only
   type permitted to change the filesystem, and it can only create a folder and move a
   file. A CI test greps the whole engine for destructive APIs and fails the build.
2. **Anything persisted needs a migration test.** A field added to a `Codable` type
   without `decodeIfPresent` and a default has already cost this project every watched
   folder once. That class of bug does not ship twice.

## Sign-off (DCO)

Commits must carry a `Signed-off-by` line certifying the
[Developer Certificate of Origin](https://developercertificate.org/):

```
git commit -s -m "your message"
```

There is no CLA. Sign-off is enough.

## Building

```bash
git clone https://github.com/evdeepak120202/tidewell
cd tidewell
./Scripts/make-signing-cert.sh    # once — see below
./Scripts/build.sh
./Scripts/install.sh
swift test --arch arm64
```

**Always use the signing certificate, never ad-hoc.** An ad-hoc signature has no
certificate, so the designated requirement is a bare hash of that exact binary and changes
on every rebuild. macOS then silently drops the app's folder-access grants and login-item
registration, while System Settings still shows them as enabled — which looks like a
broken app rather than an unauthorised one.

Run the installed copy, not `build/Tidewell.app`: `build.sh` deletes and recreates that
bundle, pulling the executable out from under a running process.

## Style

- Swift 6 language mode, strict concurrency, **no `@preconcurrency`**.
- `TidewellCore` imports no SwiftUI and no UI code. The engine stays headlessly testable,
  which is the point of the rule. Two exceptions exist and are data extraction, not
  interface: **PDFKit** and **Vision**, used to pull a text sample out of a document for
  on-device classification. Adding a third needs a good reason.
- Comments explain *why*, not what. If a line needs a comment to say what it does, rewrite
  the line.
- Warnings are errors in debug builds.

## Tests

Every PR needs tests for: new safety behaviour, any persistence change, and any bug that
reached a user. `swift test --arch arm64` must pass on both architectures.

## Translations

The package declares `defaultLocalization: "en"`, so user-facing strings are extractable
without touching Swift. Tidewell ships English only today — a translation PR is welcome,
and should add a `.lproj` for its locale rather than editing string literals in place.

Two things translators should know: the app deliberately avoids the words *clean*,
*remove* and *delete* when describing what it does, because it does none of those. Files
are **filed**, **set aside**, **archived** and **put back**. Please keep that distinction
in your language — it is the product's central promise, not a style preference.

## Pull requests

- One concern per PR.
- Update `CHANGELOG.md` in the same PR.
- Conventional commit subjects (`fix:`, `feat:`, `docs:`).
- CI must be green: build (arm64 + universal), tests, destructive-API grep, network grep.
