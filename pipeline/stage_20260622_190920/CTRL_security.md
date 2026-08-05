# Security Review — injection, auth, secrets, surface area

Scope reviewed:
- `README.md`
- `Sources/CanaryTranscriber/main.swift`

## Checks performed
- Traced the new `speakerAliases` data flow from UI input → Swift `BatchConfig` JSON → embedded Python script → `.canary.md` / `.canary.json` outputs.
- Verified process execution uses argument arrays (`Process.arguments`, `subprocess.run([...])`) rather than shell interpolation.
- Checked for new authentication, credential, token, or network-handling code paths.
- Checked whether any new data is persisted beyond local app storage / local output files.

## Findings
- **Injection:** No command/shell injection path introduced. Speaker aliases are serialized to JSON and consumed as data only. They are not interpolated into shell commands.
- **Auth:** No auth flows or privilege boundaries were added or changed.
- **Secrets:** No secrets are introduced, read, or persisted by this change. The new persistence uses `@AppStorage`, i.e. local user defaults.
- **Surface area:** The only meaningful expansion is local storage of speaker alias text and richer local markdown/json transcript exports. No new network endpoints or external services were added.

## Verdict
No blocking security issues found in this change set.

RESULT: PASS
