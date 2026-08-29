# Security Policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](../../security/advisories/new) rather than a public issue.

Expect an acknowledgement within 72 hours and an assessment within 7 days. If a fix is
needed, you will be credited in the release notes unless you would rather not be.

## Scope

Tidewell moves files on a user's machine, so the security surface is narrower than most
apps but the consequences of a bug are direct. In scope:

- Anything that causes Tidewell to **destroy or overwrite** user data. The engine has no
  delete, trash or overwrite call and a CI test enforces that; a way around it is a
  serious bug.
- Anything that causes it to act **outside a watched folder**, including path traversal
  through a crafted filename or a symlink.
- Anything that makes it act on **untrusted file contents as instructions** — see the AI
  guardrails below.
- Privilege or sandbox escape, or execution of code from a watched folder.

Out of scope: the app deliberately has no network code, no accounts, no telemetry and no
server. There is nothing to attack remotely.

## Design guarantees

These are enforced in code and tested, not merely intended:

| Guarantee | Enforced by |
| --- | --- |
| Never deletes or overwrites | `FileMover` has no such API; a CI grep over `TidewellCore` fails the build if one appears |
| Never touches folders | `SafetyGuard` rejects directories, packages, symlinks and aliases |
| Never leaves the machine | CI grep for `URLSession`, `NWConnection`, `CFSocket` and friends |
| Never acts on a file still being written | `StabilityGate` samples twice; partial-download extensions skipped |
| Every action reversible | Journal records both ends of every move |

## On-device AI

When the optional on-device classification is enabled, **file contents are treated as
untrusted input**. A document can contain text attempting to redirect the model. The
structural mitigation is that the model returns one label from a closed set and never a
path, so the worst achievable outcome is a misfiled file — visible in the preview and
reversible. The model has no tool access, no filesystem access and no network access.

## Verifying a build

Releases are not notarised (notarisation requires a paid Apple Developer membership this
project does not have). Instead:

- Every release publishes SHA-256 checksums.
- `Scripts/build.sh` is deterministic; CI builds the same artifact from the same tag.
- The recommended install compiles from source on your own machine, so you are running
  code you can read.
