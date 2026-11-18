# Contributing

Thanks for wanting to help!

1. Build the development app: `./Scripts/build-app.sh`. It keeps its own data, separate from an installed moi.
2. Run the tests before and after your change: `./Scripts/test-core.sh`, `./Scripts/test-workspace.sh`, `./Scripts/test-refinement.sh`.
3. Test with made-up files and photos only. The test scripts use temporary folders; keep it that way.
4. Keep it native: prefer Apple frameworks over new dependencies. If you add one, record its license in `THIRD_PARTY_NOTICES.md`.
5. Match moi's voice in anything people read: short, warm, plain words. "Put back", not "revert the operation".
6. Anything that changes files, apps or settings must show what will happen first and be undoable.

Open an issue to talk through bigger ideas before building them.
