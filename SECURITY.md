# Security

## Reporting a problem

Please open a [GitHub issue](https://github.com/withmarshallphan-spec/moi/issues) for bugs. For anything sensitive, ask for a private contact in an issue first and don't post details. Never include API keys, personal files or real photos; a small made-up example is perfect.

## How moi stays safe

- **AI output is untrusted.** A brain can only choose from moi's fixed list of actions (`MoiActions` in `Workspace/Intelligence.swift`). There's no shell, no arbitrary file access and no permanent deletion. Deleting plan items, quitting apps and Dock changes wait for a yes.
- **Files are moved, never deleted.** Every clean-up is recorded so it can be put back, and an occupied destination is never overwritten. Trash only takes files you pick, and moi never empties it.
- **Photos are read-only.** moi can make albums but never edits or deletes photos.
- **Apps quit politely.** Normal quit requests only, so apps can ask you to save.
- **Keys** live in the Keychain, are only sent over HTTPS to the provider they belong to, and local brains are restricted to this Mac (localhost).
- **Your data files** are written atomically. A file moi can't read is kept and set read-only instead of being overwritten.

## Known limits

Builds from source are ad-hoc signed, not notarised. macOS may ask again for permissions and Keychain access after each rebuild. There has been no independent security audit.
