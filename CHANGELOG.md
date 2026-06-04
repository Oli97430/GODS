# Changelog

All notable changes to **GODS** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/) · Versioning: [SemVer](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/Oli97430/GODS/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/Oli97430/GODS/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Oli97430/GODS/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Oli97430/GODS/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Oli97430/GODS/releases/tag/v0.5.0
