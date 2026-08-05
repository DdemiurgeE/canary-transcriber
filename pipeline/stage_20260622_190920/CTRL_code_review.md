# Code Review — readability, maintainability, patterns

## Findings

1. **Python environment bootstrap now passes package names as separate arguments**  
   `setupPythonEnvironment()` now builds the pip requirement list as an array and passes it as separate `Process.arguments` entries, so the venv bootstrap path is readable and correct.

2. **Model cache status now distinguishes cached vs update-available**  
   `checkModelCache()` now compares the local Hugging Face revision against remote `model_info(...).sha` when available, mapping the result to `CACHED` or `UPDATABLE` instead of a no-op branch. The UI already handles `.updatable`.

3. **README list nesting is now consistent**  
   The Canary v2 Russian transcription note is indented as a nested bullet under built-in profiles.

4. **Shared alias helpers now live in a testable core module**  
   `BatchConfig`, `speakerAliasesStorageKey`, and `parseSpeakerAliasesText(_:)` were moved into `CanaryTranscriberCore`, which improves maintainability and makes the parser/config round-trip testable without importing the app target.

## Result

RESULT: PASS