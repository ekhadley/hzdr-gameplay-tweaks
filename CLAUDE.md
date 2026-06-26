# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows DLL mod for **Horizon Zero Dawn Remastered** (HZDR). It injects into the game by masquerading as `winhttp.dll` (a DLL proxy), then hooks the game's code at runtime to add a cheat/debug menu and a set of gameplay tweaks. The game itself is a Decima-engine title; much of the code reverse-engineers Decima's RTTI system and core classes (the `HRZR` namespace mirrors the game's own types).

There is no game source — this mod operates entirely against the shipped game binary by pattern-scanning for functions and patching them in memory.

## Building

Windows-only (MSVC 2022 17.9.6+, CMake 3.26+, vcpkg). Dependencies are pulled via vcpkg manifest (`vcpkg.json`): detours, imgui (dx12 + win32), spdlog, toml++, xbyak, quickdllproxy. `detours` uses an overlay port in `vcpkg-ports/`.

- **VS UI:** open the folder, pick a preset (`Universal Release x64` or `Universal Debug x64`), build.
- **Script:** `.\Make-Release.ps1` builds all configs and archives them to `bin/built-packages`.
- **Output:** the DLL is named `winhttp.dll`. Set `GAME_ROOT_DIRECTORY` in `CMakeUserEnvVars.json` and the post-build step copies `winhttp.dll` into the game folder automatically.

C++23, `/GR-` (RTTI off), `/W4`. There is no test suite — verification means running the game.

## Configuration

`resources/mod_config.ini` is the user-facing config, parsed as **TOML** despite the `.ini` extension. `ParseSettings`/`PostProcessSettings` in `ModConfiguration.cpp` turn it into the global `ModConfiguration` struct. Additional `mod_*.ini` files in the game directory are merged on top (for third-party add-on configs). Many high-level toggles (e.g. `UnlockMapBoundaries`, `EnableFreeCrafting`) are implemented in `PostProcessSettings` by synthesizing **asset overrides** — they are not special-cased anywhere else.

## Architecture

Initialization flow (`DllMain.cpp` → `ModConfiguration::Initialize`):
1. Parse config.
2. `Offsets::Initialize()` — pattern-scan the game image for every declared signature.
3. `Hooks::Initialize()` — commit every declared hook transaction.

Three pillars:

### Offsets (`source/Hooking/Offsets.*`)
Compile-time byte-pattern literals (`Signature("E8 ? ? ? ? 48 8B ...")`) register themselves into a global list. At startup, `Offsets::Initialize` scans the loaded game image (a hand-written SSE vectorized scanner) and resolves each to an address. **If any signature fails to resolve, init aborts** — this is the expected failure mode when the game updates. `Offset` supports `.AsAdjusted()` and `.AsRipRelative()` for following relative operands.

### Hooks (`source/Hooking/Hooks.*`, Memory.*)
`DECLARE_HOOK_TRANSACTION(Name) { ... }` registers a lambda that runs at init to install hooks. Inside, use `Hooks::WriteJump` / `WriteCall` / `WriteVirtualFunction` / `RedirectImport` (templated overloads preserve function signatures). Backed by MS Detours + xbyak. Hook transactions are scattered across the files that own each feature (grep `DECLARE_HOOK_TRANSACTION`): `GameModule.cpp` (timescale), `NxDXGIImpl.cpp` (the DXGI Present hook that drives all UI rendering), `AIManagerGame.cpp`, `ThirdPersonPlayerCameraComponent.cpp`, `LoggingHooks.cpp`, `RTTIScanner.cpp`.

### RTTI / asset patching (`source/HRZR/`, `ModCoreEvents.cpp`)
The `HRZR` namespace re-declares Decima engine types (in `HRZR/Core/`, `HRZR/PCore/`) so the mod can read/write game objects by memory layout. `RTTIScanner` walks the game's RTTI graph to build a name→type map (`RTTI::FindTypeByName`). `ModCoreEvents` is the heart of gameplay tweaks: it hooks asset (core file) load/unload, and as each `RTTIRefObject` is read it applies patches keyed by RTTI type or UUID. Two patch kinds:
- **Value patches** — set a member path to a string value via `RTTIObjectTweaker` (these come from config asset overrides; a `@`-prefixed path means a ref-pointer swap).
- **Callback patches** — C++ lambdas for logic too complex for a value string (auto-loot, inventory stack sizes, object caches). Defined in `RegisterHardcodedPatches`.

`ModCoreEvents` also maintains live caches of loaded objects (spawn setups, weather setups, inventory items, AI factions) that the debug UI reads.

### Debug UI (`source/HRZR/DebugUI/`)
Dear ImGui, rendered from the hooked DXGI `Present` (`NxDXGIImpl::HookedPresent` → `DebugUI::RenderUI`). `MainMenuBar` holds runtime cheat state (timescale override, freecam, etc.); per-feature windows (`EntitySpawnerWindow`, `PlayerInventoryWindow`, `WeatherSetupWindow`, `LogWindow`, ...) register via `DebugUI::AddWindow`. The `LogWindow::LogSink` is wired in as an spdlog sink so in-game logging and the log window share one stream.

### DLL proxy (`source/DllProxy/`)
`WinHttpExports.*` uses the QuickDllProxy header to forward all real `winhttp.dll` exports to the system DLL, so the game runs normally while our code loads. Export list is `WinHttpExports.inc`.

## Conventions

- `.clang-format` is authoritative (tabs, Allen-style braces, wide column limit). Match surrounding style.
- Errors during init are loud and fatal (throw → `MessageBoxW`), by design — pattern-scan or hook failures should not silently degrade.
- `XorStr` (in `PCH.h`) obfuscates string literals in release builds; used for sensitive/identifying strings.
- When adding a gameplay tweak: prefer a config-driven asset override in `PostProcessSettings` if it's just a member value; reach for a callback patch or a new hook transaction only when that's insufficient.

## Known issues

- **Concentration sensitivity (`ConcentrationSensitivity.cpp`):** the fix gates purely on `m_WorldTimeScale < 1`, on the assumption that concentration (aim slow-mo) is the only thing that slows the world. That's wrong — the **weapon wheel** also triggers the same slowdown, so the sensitivity correction over-boosts the mouse for the brief slowed window around opening/closing the wheel. To fix properly, gate on the player actually aiming rather than on timescale. The previous aim-flag gate (controller `+0x47D8 & 1`) read 0 during concentration, so a different aim signal is needed.

- **Concentration sensitivity feels "off" vs. original (non-remaster) HZD:** the correction works, but the feel during concentration isn't quite the same as the original game. Symptom only; cause unconfirmed. The correction is live-tracked (`k = 1 + correction*(1/m_WorldTimeScale − 1)` recomputed per frame, so it ramps smoothly with the slow-mo ease-in/out), so a binary toggle is *not* the cause. The same weird feel also occurs during **weapon-wheel** concentration, which does **not** change FOV — so FOV is ruled out as the (sole) cause. The leading hunch is a **timing mismatch**: a delay between when concentration actually ends and when we stop applying (or fully unwind) the correction. Possible explanations, roughly in order of suspicion:
  - **Timing/lag between the real slowdown and `m_WorldTimeScale`.** If the quantity that actually scales the mouse delta ends/ramps on a different schedule than the global `m_WorldTimeScale` we read, we keep over-correcting during the tail (or under-correct on entry). Worth instrumenting: log `m_WorldTimeScale` against an independent "is concentration active" signal across a full in/out cycle and look for a phase offset.
  - **We scale the post-processed look vector.** The float2 at controller `+0x4790` is consumed after any smoothing/acceleration, which itself lags the raw input by a few frames. Scaling a lagged/smoothed output by a per-frame-varying `k` mismatches `k` (current frame) against input from earlier frames — a built-in timing skew during any ramp, independent of FOV.
  - **`m_WorldTimeScale` isn't the exact delta-time divisor.** Our `k = 1/t` assumes the engine scales mouse delta by precisely `m_WorldTimeScale`. If the real factor differs (a separate aim-slomo modifier, or a nonlinear curve), `k` over-/under-corrects, most visibly mid-ramp.
  - **FOV ease (aim concentration only).** For *aim* concentration (not the weapon wheel) FOV/zoom also ramps, changing perceived on-screen sensitivity; we don't compensate that axis. Likely a secondary contributor at most, since the symptom persists without any FOV change.
  - **Remaster changed the mouse aim path** relative to original HZD (the engine compensates the motion/gyro path via `MotionAimingSlomoSensitivityModifier` but not mouse), so matching the original's feel may require a different correction model entirely, not just cancelling the timescale.
