# Support

- **A bug** — open an [issue](../../issues/new/choose) with your macOS version, chip
  (Apple silicon or Intel), and what you expected versus what happened.
- **A question or idea** — [Discussions](../../discussions).
- **A security issue** — see [SECURITY.md](SECURITY.md). Please do not open a public issue.

## Out of scope

- Windows and Linux. Tidewell is built on FSEvents and AppKit.
- Cloud sync, accounts, and anything that sends files anywhere. The app has no network
  code by design and that is not going to change.
- Running arbitrary scripts on file arrival. A folder-watching background agent that can
  execute shell is a persistent security hole; use Shortcuts via App Intents instead.

## Before filing a bug about a file that did not move

Open the folder in Tidewell and read the preview — it names every file it is leaving alone
and why. The common answers are: it is still downloading, it is inside its arrival delay,
it is a folder, or a rule excludes it.
