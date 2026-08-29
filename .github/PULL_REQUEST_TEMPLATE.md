## What this changes

<!-- One concern per PR. -->

## Checklist

- [ ] `swift test --arch arm64` passes
- [ ] Builds on arm64 **and** x86_64
- [ ] `CHANGELOG.md` updated
- [ ] Commits signed off (`git commit -s`)

If this touches anything persisted:

- [ ] New fields use `decodeIfPresent` with a default
- [ ] A migration test decodes a file written **before** this change

If this touches the engine:

- [ ] No `removeItem`, `trashItem`, `replaceItem` or `unlink` added to `TidewellCore`
- [ ] Safety behaviour has a test
