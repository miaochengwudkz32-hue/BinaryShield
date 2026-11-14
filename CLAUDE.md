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
- Run on Linux: protection runs on Windows only (see Linux Deployment Plan)

## Delivery Plan

| Version | Scope                                              | Acceptance Test                                          | Status |
|---------|----------------------------------------------------|----------------------------------------------------------|--------|
| v0.1    | Namespace classifier + ConfuserEx2 config generator | Config file correctly excludes all Avalonia.* namespaces | Done (1A, 1B) |
| v0.2    | CLI wrapper: one command runs full pipeline         | Protected binary runs; Avalonia UI smooth                | Wrapper done (1C); real-app window verified; target DLL pending |
| v0.3    | Native binary metadata reader (LIEF-based)          | Reads PE/ELF metadata without crashing                   | Not started |
| v1.0    | Unified CLI, all targets, test suite                | All benchmarks pass; protection on Windows, protected output runs on Linux (see Linux Deployment Plan) | Not started |

## Linux Deployment Plan (decided 2026-11-01)

**Decision: Plan A.** Protection stays on Windows. Modules 1A–1C and ConfuserEx2 1.6.0 run on Windows, unchanged. The protected output is then copied to Linux and run there. BinaryShield itself never runs on Linux.

**Precondition (confirmed 2026-11-08):** the target program is an Avalonia program, and it must run on both Windows and Linux. The WPF DLL analyzed on 2026-11-05 is not the target and is void. Avalonia runs on Linux, so this plan applies again. The target framework is still unverified (see prerequisite 1).

**Why:**
- ConfuserEx2 keeps its `normal` protection strength for .NET Framework 4.x. For .NET 8, ConfuserEx2 cannot process the assemblies, so **Obfuscar 3.0 beta is the protection engine for .NET 8 targets**. Its protection set is much thinner (mainly renaming and string hiding), so .NET 8 targets get less protection.
- No porting: 1A–1C stay on .NET Framework 4.x. There is no .NET 8 rewrite, and no Obfuscar adapter (Module 2A) exists yet.
- Protected managed assemblies are IL, so the same DLLs can run on Linux once the runtime matches.

**Not planned:** porting 1A–1C to Linux; protecting native binaries on Linux (the v0.3 LIEF work stays separate).

**Prerequisites not yet verified:**
1. **Target program framework.** Our test app targets .NET Framework 4.7, which does not run natively on Linux. It would need Mono, and Avalonia on Mono is untested. If the target program targets .NET 6 or later, ConfuserEx2 1.6.0 cannot protect it: it fails even with no protections (`preset="none"`), with `TypeResolveException` for `System.Runtime 8.0.0.0` (tested 2026-11-02, see the progress log). The root cause is inferred and no workaround was tried. Module 1A reports `targetFramework`; check it on the target program DLL first.
2. **Native libraries must be replaced.** 1C copies Windows natives (for example `libSkiaSharp.dll` in `x64\` and `x86\`) into `protected\`. Those do not load on Linux. The Linux package needs the Linux natives (for example `libSkiaSharp.so`). Native files are not IL, so ConfuserEx2 does not touch them. The package step is not written yet.
3. **Platform-specific code is not checked.** Windows-only P/Invoke, registry access and backslash paths are not detected by the static checks. They need manual review or a run on Linux.

**Next steps:**
a. Obtain the target program DLL; run Module 1A and record `targetFramework`. If .NET Framework 4.x: protect with ConfuserEx2 via `module_1c`. If .NET 8: protect with Obfuscar 3.0 beta (no adapter yet).
b. Choose the Linux runtime (Mono or .NET) based on (a).
c. Build a Linux test package: Linux natives plus the protected managed DLLs.
d. Start the protected app on Linux; verify the window and that the Avalonia XAML loads. WSL2 can host this step, but the Module 1A environment check found WSL not installed on this machine, so it would need installing first.

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
    ├── benchmarks/        ← one automated test script per module
    └── dotnet8_avalonia/  ← .NET 8 Avalonia list/binding/click app; Obfuscar end-to-end test (run_test.ps1)
```

## Locked Dependencies (do not change without updating dependencies.md)

| Purpose                        | Tool / Library       | Source                        |
|--------------------------------|----------------------|-------------------------------|
| .NET assembly reading          | dnlib 4.5.0          | NuGet (in repo: module_1a/dnlib.dll) |
| .NET protection engine         | ConfuserEx2 1.6.0    | github.com/mkaring/ConfuserEx (release v1.6.0) |
| .NET 8 protection engine       | Obfuscar 3.0.0-beta.22 | NuGet `Obfuscar.GlobalTool` 3.0.0-beta.22 (MIT) |
| JSON parsing (.NET FX)         | System.Web.Extensions | .NET Framework 4.x (framework assembly) |
| PE / ELF reading               | LIEF                 | github.com/lief-project/LIEF (not yet used) |
| C# compiler                    | csc.exe (.NET FX 4.x) or Visual Studio 2022 MSBuild | system-provided |
| Version control                | Git                  | system-provided               |

Details, hashes and download methods: `dependencies.md`.

## Development Workflow (read before every session)

### Session startup (mandatory)
1. Read `CLAUDE.md`
2. Read `the progress log`
3. Confirm current module, then begin

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

STEP 9 — Update the progress log
  Write: what was completed / what is next / any unresolved issues

STEP 10 — Plain-language decision log
  For every significant technical decision made during this session,
  write one plain sentence explaining why that choice was made
```

### Stuck rule
Same error after 5 attempts → stop immediately → write details to `the stuck log` → wait for human input.
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
7. **Plain-language summaries** — after each session, write a one-paragraph summary in the progress log so the next session can start without re-reading everything
8. **Cross-review after PASS** — send a compact excerpt (≈5 KB) to DeepSeek and Claude; never paste whole files with deep thinking on (it overflows the other model's context)
9. **Rollback via git** — if a module is fundamentally wrong, revert to the last commit rather than patching on top
10. **No unsolicited library additions** — ask before adding any dependency not in dependencies.md
11. **Check the model label** — when using claude.ai, confirm the model label is Opus 5.5 before trusting a reply; it has been routed to another model

## Session Start Command

Copy this, fill in the module name, and send it to Claude Code:

```
Read CLAUDE.md and the progress log first.

Today's task: [MODULE NAME — e.g. "Module 1C — follow-up"]

Follow every step in the workflow section of CLAUDE.md in order.
Avalonia rule, stuck rule, and git rule apply throughout.
Explain key decisions in plain language as you go.
```

## Current Status

**Module 1A — COMPLETE ✅** — namespace classifier (`module_1a.exe`), read-only, dnlib. Initial commit `3302391`.

**Module 1B — COMPLETE ✅** — ConfuserEx2 `.crproj` generator (`module_1b.exe`). Current commits: `8c3c79e` (initial), `663d333` (review fixes), `51ea197` (CompiledAvaloniaXaml exclusion; `ref proxy` removed from base rule). Benchmark all PASS.

**Module 1C — COMPLETE ✅** — CLI wrapper (`module_1c.exe protect`). Commits: `fe065ac` (initial), `2ff8131`, `093da0c`, `38bac04`, `91d6685`, `b3aa69f` (review fixes; app config and dependency subdirectories copied; checks normalised). Benchmark all PASS.

**Real-app verification — PASSED** (`6ce4b71`, see the progress log 2026-11-01):
- Test app: Avalonia 11.0.10, FluentTheme, .NET Framework 4.7, built with VS 2022 MSBuild (XAML precompiled).
- Pipeline exit 0; checks a–f PASS; protected exe starts and shows its window.
- Not yet verified: the target program's real DLL (not yet received); UI interaction (scrolling, clicks, data binding).

**.NET 8 + Avalonia list test — PASSED on Windows (2026-11-12, see the progress log 2026-11-12; `tests/dotnet8_avalonia/`):**
- Test app: Avalonia 11.0.10, .NET 8, ListBox with 10,000 items, data binding, button click, wheel scroll.
- Obfuscar 3.0.0-beta.22 with `SkipNamespace Avalonia*` and `SkipNamespace CompiledAvaloniaXaml*`: all 8 checks pass on both the plain and the protected build (`run_test.ps1`, exit 0).
- Windows: plain and protected builds both pass 9/9 in the final run (`run_test.ps1`).
- Linux (WSL2 Ubuntu through WSLg): NOT passed yet. The protected build passed 9/9 in the final run, but the wheel check (5 notches) is intermittent in both builds (3 of 5 in some runs). Root cause not found.
- Simulated mouse input. This test app is not the target program.

**Known open risks**
- ConfuserEx2 1.6.0 (2022) — maintenance status unknown; its rule syntax was verified against this version only.
- Protection strength reduced for Avalonia-related code (`ref proxy` and `resources` removed; `CompiledAvaloniaXaml` excluded).
- TOCTOU window between CLI verification and execution (accepted; see the progress log).
- Timeout and process-tree kill branches have no automated test.
- Linux deployment: target runtime and native libraries unverified (see Linux Deployment Plan).
- ConfuserEx2 1.6.0 cannot process .NET 8 assemblies (tested 2026-11-02). The current toolchain (ConfuserEx2 + 1A–1C) is limited to .NET Framework 4.x.
- .NET 8 with Obfuscar 3.0 beta: the Windows test app (ListBox with 10,000 items, data binding, button click, wheel scroll) passes with the SkipNamespace rules on Windows (2026-11-12). Linux: not passed yet (intermittent wheel count, see Current Status). Not tested: frame-rate smoothness, Avalonia virtualization internals, DataGrid, complex XAML, large applications, the target program's real code.
- Obfuscar 3.0 beta is not integrated: `module_1c` only drives ConfuserEx2, so .NET 8 protection has to be run by hand until an adapter (Module 2A) exists.

**Next task:**
1. Linux verification of the test app is NOT passed yet. The app runs on Ubuntu (WSL2, WSLg), but the wheel check is intermittent in both builds. Decide: debug the input path (plan: send wheel events with xdotool inside Ubuntu), or accept it as a known flake. Script: `tests/dotnet8_avalonia/run_linux_test.ps1`.
2. Report phase-1 completion only after the user confirms the scope. Passing the test app is not the same as passing the target program.
3. The target program's full Avalonia run directory is still pending. Module 1A has read its metadata only (`targetFramework` .NET 8); it has not been protected or run. When it arrives: run Module 1A, protect it with Obfuscar using the same SkipNamespace rules, then test on Windows and Linux.
Then decide whether to start native work (3A/3B, LIEF) for v0.3.
