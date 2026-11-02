# CLAUDE.md — BinaryShield 工作手册（给 Claude Code 看）

This file is the working manual for Claude Code on this project.
Public-facing description: `README.md`. Detailed usage: `USAGE.md`.

## Project scope

An integration and configuration layer that wraps existing open-source .NET and
native binary processing libraries into a unified, Avalonia-compatible build pipeline.

This project does not implement any obfuscation algorithms. It configures, extends,
and glues together established open-source tools — ConfuserEx2 for .NET (native side:
LIEF, not started) — and adds Avalonia-specific compatibility rules that existing tools lack.

**Does:**
- Download, configure, and invoke ConfuserEx2 as a subprocess
- Read .NET assemblies using dnlib to classify namespaces
- Generate a ConfuserEx2 config file (.crproj) with Avalonia exclusion rules
- Wrap everything in a single CLI command (`module_1c.exe protect`)

**Does not:**
- Implement string encoding, IL transformation, or any protection algorithm
- Replace ConfuserEx2 — it drives ConfuserEx2 as an external tool
- Modify any input binary

## Delivery Plan

| Version | Scope                                              | Acceptance Test                                          | Status |
|---------|----------------------------------------------------|----------------------------------------------------------|--------|
| v0.1    | Namespace classifier + ConfuserEx2 config generator | Config file correctly excludes all Avalonia.* namespaces | Done (1A, 1B) |
| v0.2    | CLI wrapper: one command runs full pipeline         | Protected binary runs; Avalonia UI smooth                | Wrapper done (1C); real-app window verified; real-world DLL pending |
| v0.3    | Native binary metadata reader (LIEF-based)          | Reads PE/ELF metadata without crashing                   | Not started |
| v1.0    | Unified CLI, all targets, test suite                | All benchmarks pass on Windows + WSL2                    | Not started |

## Repository Layout

```
He/
├── README.md              ← public description (for humans)
├── USAGE.md               ← detailed usage (for humans)
├── CLAUDE.md              ← this file (for Claude Code)
├── dependencies.md        ← every library, version, and download method
├── src/
│   ├── dotnet/
│   │   ├── module_1a/     ← namespace classifier (dnlib, read-only)
│   │   ├── module_1b/     ← ConfuserEx2 config generator
│   │   └── module_1c/     ← CLI wrapper for full .NET pipeline
│   └── native/
│       ├── module_3a/     ← PE metadata reader (LIEF) — not started
│       └── module_3b/     ← ELF metadata reader (LIEF) — not started
└── tests/
    ├── test_files/        ← sample binaries
    └── benchmarks/        ← one automated test script per module
```

## Locked Dependencies (do not change without updating dependencies.md)

| Purpose                        | Tool / Library       | Source                        |
|--------------------------------|----------------------|-------------------------------|
| .NET assembly reading          | dnlib 4.5.0          | NuGet (in repo: module_1a/dnlib.dll) |
| .NET protection engine         | ConfuserEx2 1.6.0    | github.com/mkaring/ConfuserEx (release v1.6.0) |
| JSON parsing (.NET FX)         | System.Web.Extensions | .NET Framework 4.x (framework assembly) |
| PE / ELF reading               | LIEF                 | github.com/lief-project/LIEF (not yet used) |
| C# compiler                    | csc.exe (.NET FX 4.x) or Visual Studio 2022 MSBuild | system-provided |
| Version control                | Git                  | system-provided               |

Details, hashes and download methods: `dependencies.md`.

## Development Workflow (read before every session)

### Session startup (mandatory)
1. Read `CLAUDE.md`
2. Confirm current module, then begin

### Per-module order (do not skip any step)

```
STEP 1 — Spec doc
  Write plain-language description: input / output / approach / edge cases
  → STOP and wait for human confirmation before continuing

STEP 2 — Benchmark first
  Write the automated test script before any feature code
  The test must be runnable and report PASS or FAIL for each criterion
  → STOP and wait for human confirmation before continuing

STEP 3 — GitHub research
  Search for existing implementations of this exact feature
  Read the relevant source code and summarize the approach
  Prefer calling an existing library over writing new logic

STEP 4 — Feature code
  Use only locked dependencies (see dependencies.md)
  Prefer configuration and invocation over reimplementation

STEP 5 — Run benchmarks
  All tests must PASS before the module is considered complete
  Do not move on with any failing test

STEP 6 — Self-review
  Switch to "code reviewer" role
  Find and fix problems in the code just written
  Commit only after review is complete

STEP 7 — Git commit
  Commit with a descriptive message
  Every passing module gets its own commit — this is the rollback point

STEP 8 — Cross-review (DeepSeek and Claude)
  Paste a compact excerpt of the module code to BOTH DeepSeek and Claude (Opus 5.5)
  Verify each claim against the code before acting on it
  Fix what is real, then make a second commit if needed

STEP 9 — Update the session log
  Write: what was completed / what is next / any unresolved issues

STEP 10 — Plain-language decision log
  For every significant technical decision made during this session,
  write one plain sentence explaining why that choice was made
```

### Stuck rule
Same error after 5 attempts → stop immediately → write details to a blocker note → wait for human input.
Do not retry. Do not try a different approach without human confirmation.

### Avalonia rule
Namespaces `Avalonia` and `Avalonia.*` and `CompiledAvaloniaXaml` and `CompiledAvaloniaXaml.*`
must be classified as excluded. Pass this exclusion to the ConfuserEx2 config generator.
For excluded namespaces, remove all 12 protections (see `src/dotnet/module_1b/spec.md` §3).
The base rule removes `resources` and `ref proxy` (see `module_1b/spec.md` §6 for why).

### Git rule
After every module reaches all-PASS: `git add -A && git commit -m "<module>: all benchmarks pass"`
This is the safety net. If a later module breaks something, this is the rollback point.

## Token efficiency rules (follow these to avoid wasting compute)

1. **Benchmark first** — never write feature code without a runnable test already in place
2. **Spec before code** — always write the spec doc and wait for confirmation first
3. **GitHub before writing** — search for existing code before implementing anything new
4. **Locked stack** — never re-evaluate library choices mid-session; they are already decided
5. **Stuck rule** — 5 failures = stop; do not loop; loops waste tokens without progress
6. **One module at a time** — complete and commit one module fully before starting the next
7. **Plain-language summaries** — after each session, write a one-paragraph summary in the session log so the next session can start without re-reading everything
8. **Cross-review after PASS** — send a compact excerpt (≈5 KB) to DeepSeek and Claude; never paste whole files with deep thinking on (it overflows the other model's context)
9. **Rollback via git** — if a module is fundamentally wrong, revert to the last commit rather than patching on top
10. **No unsolicited library additions** — ask before adding any dependency not in dependencies.md
11. **Check the model label** — when using claude.ai, confirm the model label is Opus 5.5 before trusting a reply; it has been routed to another model

## Session Start Command

Copy this, fill in the module name, and send it to Claude Code:

```
Read CLAUDE.md first.

Today's task: [MODULE NAME — e.g. "Module 1C — follow-up"]

Follow every step in the workflow section of CLAUDE.md in order.
Avalonia rule, stuck rule, and git rule apply throughout.
Explain key decisions in plain language as you go.
```

## Current Status

**Module 1A — COMPLETE ✅** — namespace classifier (`module_1a.exe`), read-only, dnlib. Initial commit `3302391`.

**Module 1B — COMPLETE ✅** — ConfuserEx2 `.crproj` generator (`module_1b.exe`). Current commits: `8c3c79e` (initial), `663d333` (review fixes), `51ea197` (CompiledAvaloniaXaml exclusion; `ref proxy` removed from base rule). Benchmark all PASS.

**Module 1C — COMPLETE ✅** — CLI wrapper (`module_1c.exe protect`). Commits: `fe065ac` (initial), `2ff8131`, `093da0c`, `38bac04`, `91d6685`, `b3aa69f` (review fixes; app config and dependency subdirectories copied; checks normalised). Benchmark all PASS.

**Real-app verification — PASSED**:
- Test app: Avalonia 11.0.10, FluentTheme, .NET Framework 4.7, built with VS 2022 MSBuild (XAML precompiled).
- Pipeline exit 0; checks a–f PASS; protected exe starts and shows its window.
- Not yet verified: a real-world application DLL (pending); UI interaction (scrolling, clicks, data binding).

**Known open risks**
- ConfuserEx2 1.6.0 (2022) — maintenance status unknown; its rule syntax was verified against this version only.
- Protection strength reduced for Avalonia-related code (`ref proxy` and `resources` removed; `CompiledAvaloniaXaml` excluded).
- TOCTOU window between CLI verification and execution (accepted risk).
- Timeout and process-tree kill branches have no automated test.

**Next task:** wait for the real-world DLL; then run the pipeline on it and verify (report.json, strings, runtime window).
Then decide whether to start native work (3A/3B, LIEF) for v0.3.
