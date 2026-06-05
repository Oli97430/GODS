# Changelog

All notable changes to **GODS** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/) · Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.11.0] — 2026-06-05
### Added
- **Smart-plug fan feedback (opt-in hardware)** — drive a TP-Link Kasa **HS-100 / HS-110** smart plug on your LAN so a fan (or any device) plugged into it turns **ON while you fly** (Iron Man flight or paraglider) and **OFF when you walk**. Fully local (Kasa protocol, no cloud), auto-discovers the plug on the network, off-thread (no VR hitch), gentle on the device, and switches the plug off on quit. New **Options → "Plug"** tab (desktop **and** VR wrist): enable toggle, optional name / fixed-IP fields, **Search** & **Test** buttons, and a live status line. Disabled-friendly: no plug on the network → silent no-op, the game is never affected.
### Fixed
- **Co-op:** drone deaths no longer crash the host — a signal-arity regression introduced by v0.10.0's enemy-variety change.
### Changed
- Internal quality pass: single source of truth for the seabed-floor formula, shared avatar AABB helper, cached arm-IK rest poses + idle-arm reset (per-frame work removed), extracted the buff-loadout derivation, deleted dead constants. No gameplay changes.

## [0.10.0] — 2026-06-04
### Added
- **Homing-missile lock-on polish** — hold your aim on a drone to acquire the lock (a camera-facing ring tightens from yellow to green with an acquisition beep), fire with a dedicated launch whoosh; the missile trails a glowing exhaust. "LOCK" readout cue.
- **Shoulder-holster cues** — holster markers glow and a haptic tick fires as your hand nears a body holster, making the VR draw/stow gesture discoverable.
- **Hands hidden when armed** — your VR hands disappear while a weapon is drawn (the weapon + shield replace them).
- **Enemy variety** — heavy (tanky), darter (fast / evasive) and shielded (frontal shield — flank it or missile it) drones, unlocked across waves.
- **Boss wave** every 5th wave — a single giant armored drone, vulnerable only during its telegraphed charge window (or to homing missiles), with a health bar and a big reward.
- **Co-op avatars** now use skeletal arm IK (the model's arms reach toward the partner's tracked hands), show the real equipped weapon, and a floating name tag.
- **Persistent inventory** — looted upgrades (damage, fire-rate, shield capacity, missiles) are KEPT across deaths and sessions and saved to disk; your character progresses over runs.
- **Underwater seabed decor** — rocks, shells, starfish and bioluminescent coral & anemones across the ocean floor near coasts (deterministic, glowing in the depths).
### Changed
- Lighter low-poly meshes for common drones (perf); detailed model kept for heavy / shielded / boss.

## [0.9.0] — 2026-06-04
### Added
- **Homing-missile secondary fire** for the plasma rifle — aim at a drone to **auto-lock** (a ring marks the target), pull the **left trigger** (VR) / middle-mouse (desktop) to launch a seeking missile that chases it down and destroys it. Ammo is **looted** from downed drones, and it works in co-op (hits route to the host).
- **Shoulder-holster weapon draw** (VR) — reach a hand to a body holster to draw/stow without the desktop toggle: right hip → revolver, over-shoulder → plasma, left hip → grenade launcher.
- **New co-op avatars** — partners now appear as a proper humanoid model (auto-scaled, kept upright, head/hands/weapon tracked) instead of placeholder shapes.
- **MIT license** and a **headless-validation GitHub Action** (boots Godot 4.6.2 and validates the project on every push).
### Changed
- **Robust co-op handshake** — a joiner reliably lands on the host's planet and spot even when connecting mid-descent (world context is re-broadcast on surface entry), and the host's simulated clock is synced so day/night and weather match.
- Switching weapons mid-combat no longer resets the drone waves.
- Internal terrain-generation perf pass (one shared per-chunk generator, cached flow-map lookups) — proven byte-identical, no world changes.
### Fixed
- Co-op netcode hardening (RPC damage validation, stale-ghost pruning), combat now pauses while the Options menu is open, enemy bolts respect terrain line-of-sight, and assorted stability fixes.

## [0.8.0] — 2026-06-04
### Added
- **Online co-op** (opt-in, P2P direct ENet): host/join by IP, shared world handshake (same seed → same planet, same landing spot), synced avatars (head + hands + weapon) in planet-space, host-authoritative drone waves, shared enemy fire (both players take hits / shield / respawn), coop wave-heal, and **shared loot** (host-authoritative pickups awarded to the nearest player).
- **Co-op UI** with no command-line flags: desktop **F2** panel (host / IP / join / leave + live status) and a **COOP** row on the VR wrist computer; host IP persisted in settings.
- **Power-landing crater** — a hard ground impact leaves a scorched decal, raised debris ring and impact glow.
- `config/version` in `project.godot` and a `CHANGELOG.md` / `release.ps1` for reproducible releases.
### Changed
- Combat rhythm: capped at **4 simultaneous drones**, each with more HP.
- Richer procedural tree foliage (hexa-bipyramid leaves + vertical color gradient).
- READMEs (EN/FR) updated: the explorer is contemplative-first with **opt-in** combat and co-op layered on top.

## [0.7.0] — 2026-06-03
### Added
- Opt-in VR combat, complete and headset-reachable: 3 weapons (revolver, plasma rifle with a real optical VR scope, grenade launcher), enemy drone waves, loot pickups, and bHaptics TactSuit X40 combat cues.
- Start immersed in the galaxy core.
### Changed
- Full audio overhaul: warmer one-shots, wide stereo ambiances at every scale, lusher generative-music pad (approved mix levels preserved).

## [0.6.0] — 2026-06-03
### Added
- Underwater world (swim mode, sea life, depth atmosphere).
- Opt-in VR combat scaffolding.

## [0.5.0] — 2026-06-02
### Added
- Initial early-access release: seamless galaxy → system → planet → surface explorer, deterministic by seed, PCVR + desktop.

[Unreleased]: https://github.com/Oli97430/GODS/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/Oli97430/GODS/compare/v0.10.1...v0.11.0
[0.10.1]: https://github.com/Oli97430/GODS/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/Oli97430/GODS/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/Oli97430/GODS/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Oli97430/GODS/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Oli97430/GODS/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Oli97430/GODS/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Oli97430/GODS/releases/tag/v0.5.0
