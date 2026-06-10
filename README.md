# GODS — A Contemplative VR Space Explorer

*Français : [README.fr.md](README.fr.md)*

**GODS** is a seamless, deterministic, **contemplative** space explorer for **PCVR** (and desktop) built in **Godot 4.6.2**. At its heart it's pure exploration — no objectives, no menus in the way — across four continuous scales: **galaxy → star system → planet (orbit) → planet surface (on foot)**, with a **survival & crafting layer**, an **optional arcade combat mode**, and **online co-op** layered on top for when you want them. Everything is **generated procedurally from a seed**, so the same seed always yields the same universe, and what you see from orbit is exactly what you walk on at ground level.

> Put on a headset, pick a star, dive toward a planet, land on it, build a shelter while the sun sets, and watch the aurora light up the night sky.

---

## ✨ Features

### Four seamless scales
- **Galaxy** — 400 star systems generated from a global seed, navigable as a 3D point cloud. Choose a system by seed or pick one of 16 named presets from the **start menu** before diving in.
- **System** — star + procedurally placed planets on live orbits (driven by a single simulated clock).
- **Planet (orbit)** — eroded planet sphere with **surface relief shading, a soft day/night terminator and an atmospheric limb glow**, shimmering oceans, rivers, lakes, clouds, atmosphere, moons & rings.
- **Surface** — streamed, chunked terrain you explore on foot, with floating-origin rebasing for precision.

### A living world
- **Deterministic terrain** with hydraulic-style erosion, carved **river beds**, **lakes**, and **waterfalls** at steep drops — coherent between the orbital view and the ground.
- **Procedural vegetation** (L-system trees: conifer / broadleaf / palm / twisted), grass, clutter and fauna, seeded per chunk and biome.
- **Biomes** driven by temperature × humidity (desert, savanna, jungle, steppe, taiga, tundra, badlands…).
- **Planet archetypes** for variety (temperate, arid, lush, frozen, volcanic, alien).
- **Craters & volcanoes** baked into the shared elevation field.
- **Day/night cycle & dynamic sky** (volumetric clouds, sunrise/sunset, **aurorae** on ~40% of planets at night).
- **Weather** (cloud cover, rain, storms with deterministic lightning) — same place + same time → same weather.
- **Moons & rings** consistent across all three scales.
- **Fauna** — turtles, birds, and other creatures wander and react to you.
- **Procedural audio** — real-time synthesized ambiences, footsteps, fauna calls, UI, and weather, mixed per scale.

### Locomotion & comfort
- **Walk**, **jump**, **Iron Man free-flight** (gravity-off armor), and a **paraglider** for soaring.
- **Comfort vignette** that tightens with speed (anti-nausea), **snap or smooth turning**, all tunable.
- **Worldspace Options panel** in VR (no need to remove the headset) + a flat desktop overlay — same settings.
- **Wrist computer** in VR (look at your left wrist): scale, coordinates, time controls, weather, inventory, crafting, building, and nearby points of interest.

### Survival & crafting
All crafting and building is **fully optional** — the contemplative explorer is intact if you ignore it.

- **Harvest**: pick fruits, **fell any tree** (axe swing) — wild, the ones you planted (once grown), and the **giant landmark trees** — mine rocks (pickaxe swing) for stone, iron, copper, gold and gem crystals.
- **Smelt** ore into ingots in the **Foundry** tab of the wrist computer.
- **Craft** structural pieces: planks, stone walls, thatch roofs, iron pillars, copper doors, golden lanterns.
- **Build**: place pieces with a ghost preview, snap to terrain, and stack them to construct shelters and towers.
- **Edit constructions**: aim at any placed piece to delete it (resource refunded) or pick it up and move it — non-destructive editing.
- **Minecraft-style cubic blocks** (1 m³): wood, stone, leaf, iron — **grid-snapped placement**, **face-stacking** (aim a face of an existing block to snap the next one flush against it). Build walls, towers, rooms block by block.
- **Plant seeds**: decompose a fruit into a seed, plant it in soil, and a new tree grows over time.

### Hardware
- **OpenXR** (Virtual Desktop / SteamVR / native) with **controllers or hand tracking**.
- **bHaptics TactSuit X40** vest support (graceful no-op if absent).
- **Desktop fallback** — runs without any headset.

### Optional combat & online co-op *(opt-in)*
- **Holstered by default** — equip a weapon from the wrist computer and an arcade encounter begins; holster it and the contemplative explorer is exactly as before.
- **3 weapons** — revolver (hitscan), **plasma rifle** (traveling bolts + a real optical VR scope you look through), **grenade launcher** (ballistic AoE) — each with its own recoil, sound and sight.
- **Enemy drone waves** that weave in front of you, telegraph their shots, and drop **upgrade loot** (heal / damage× / fire-rate× / overshield).
- **bHaptics X40** combat feedback (chest recoil, directional damage, kill/heal/shield cues).
- **Online co-op** — host or join by IP (P2P direct, ENet). Same seed → same universe, so you share the planet, see each other's avatars (head + hands), and fight the drone waves & share loot together. Strictly opt-in; **solo play is untouched**.

---

## 🖥️ Requirements

- **OS:** Windows 10/11 (x86-64), Direct3D 12.
- **GPU:** a capable PCVR GPU (developed/tuned on an RTX 3090).
- **VR (optional):** any OpenXR runtime — **Virtual Desktop (VirtualDesktopXR)**, **SteamVR**, or a native runtime — plus a connected headset. Without one, the game starts on the desktop automatically.
- **Haptics (optional):** the bHaptics Player running locally for TactSuit X40.

---

## 🚀 Install & Run (one-click)

1. Download `GODS.exe` from the [latest Release](../../releases/latest).
2. **Double-click it.** It's a single self-contained executable — no installer, no dependencies to set up.
3. For **VR**: make sure your **OpenXR runtime is active** (e.g. start Virtual Desktop streaming *before* launching, or within ~20 s of launch — the game auto-switches to VR when the headset is detected). Otherwise it runs on the desktop.

That's it.

---

## 🎮 Controls

### Desktop
| Input | Action |
|---|---|
| **WASD / ZQSD** | Move |
| **Mouse** | Look |
| **Space** | Jump |
| **F** | Toggle Iron Man flight (Space = up, C = down, Shift = boost) |
| **E** | Deploy / fold paraglider (while airborne) |
| **Left-click / Enter** | Select / descend one scale (land on a planet, etc.) |
| **Escape** | Ascend one scale / cancel placement |
| **Tab** | Open/close the Options menu |
| **Left-click** *(while placing)* | Place a piece / block |
| **X** *(aimed at a placed piece)* | Delete it (resource refunded) |
| **G** *(aimed at a placed piece)* | Pick it up and move it |

### VR — on a planet surface
| Input | Action |
|---|---|
| **Left stick** | Walk |
| **Right stick ← →** | Turn (snap or smooth) |
| **A (right)** | Jump |
| **B (right)** | Toggle Iron Man flight |
| **X (left)** | Deploy / fold paraglider (while airborne) |
| **Y (left)** | Go back up to orbit |
| **☰ menu (left)** | Open/close the worldspace Options panel |
| **Right controller aim + trigger** *(or index finger)* | Interact with panels / the wrist computer |
| **Look at your left wrist** | Wrist computer (inventory, crafting, building…) |
| **Trigger** *(while placing)* | Place a piece / block |
| **Grip (short press)** *(aimed at a piece)* | Delete it (resource refunded) |
| **Grip (hold ~0.5 s)** *(aimed at a piece)* | Pick it up and move it |

### VR — galaxy / system / planet (orbit)
| Input | Action |
|---|---|
| **Aim + trigger** | Select / descend one scale |
| **B (right)** | Ascend one scale |
| **Grip** | Grab to rotate/move the holographic view |
| **Right stick (up/down)** | Zoom |

### Wrist computer tabs
| Tab | Contents |
|---|---|
| **Sonde** | Planet probe — biome, altitude, time |
| **Temps** | Time controls (pause / fast-forward / real-time) |
| **Sac** | Inventory (items collected, eat to heal) |
| **Bâtir** | Foundry · Crafting · Blocks · Gardening |
| **Coop** | Co-op (host / join / quit) |

---

## 👥 Co-op (optional)

Play with a friend — **opt-in**, peer-to-peer by IP (LAN, or port-forward **7711** for internet). Worlds are deterministic, so only players, drones and loot travel the network.

- **Desktop:** press **F2** for the co-op panel → **Host**, or type the host's IP and **Join**.
- **VR:** use the **COOP** row on the wrist computer — Host / Join / Quit (the host IP is set once on the desktop and remembered).

The host flies down to a planet; the joiner lands on the **same spot** and you explore — and fight the drone waves — together.

---

## 🔧 Build from source

This is a standard Godot project.

1. Install **Godot 4.6.2 (stable)** — the **Forward+** renderer, **D3D12** on Windows.
2. Open the project (`project.godot`) once in the editor so it imports resources.
3. **Run:**
   - Desktop test: `godot --path . --xr-mode off`
   - VR: just `godot --path .` (OpenXR auto-initializes if a headset is present).
4. **Export a Windows executable** (single self-contained file):
   ```
   godot --headless --path . --export-release "Windows Desktop" build/GODS.exe
   ```
   (Requires the Windows export templates for 4.6.2 to be installed.)

### Headless validation (no headset needed)
- Compile all scripts: `godot --headless --path . --editor --quit`
- Integrated boot: `godot --headless --path . --quit-after 200`

---

## 🧠 Technical highlights

- **Single shared sampling hot path** (`PlanetGenerator.sample_elevation` / `sample_biome_*`) guarantees orbit ↔ surface ↔ vegetation coherence.
- **Off-thread chunk generation** (`WorkerThreadPool`) — pure, deterministic, with budgeted main-thread insertion and node pooling.
- **Seam-free terrain** via halo-based analytic normals; **geomorphing LOD** to kill popping.
- **Floating-origin rebasing** for kilometer-scale precision on foot.
- **Hydrology** (flow map + erosion) baked off-thread on first planet visit; rivers/lakes/waterfalls rendered from it.
- **Worldspace UI** (wrist computer & options panel) rendered to `SubViewport`s on quads, driven by ray/finger input re-injected as synthetic mouse events.
- **From-scratch DSP audio** feeding `AudioStreamGenerator`s (oscillators, biquads, envelopes, noise).
- **Deterministic crafting & building**: every placed object, mined rock and grown tree is reproducible from the same seed + player actions, with resource accounting and refund on removal.

---

## 📁 Project layout

```
scripts/        GDScript (generators, views, player, XR, audio/, …)
shaders/        .gdshader (terrain, water, sky, clouds, atmosphere, vignette, waterfall, …)
scenes/         Main.tscn, WristComputer.tscn, …
addons/         third-party addons (if any)
project.godot   engine config (autoloads, OpenXR, Jolt, D3D12)
```

Comments are in **French**; identifiers are in **English**.

---

## 📜 Credits & License

Created by **Oli97430**. Built with [Godot Engine](https://godotengine.org) 4.6.2.

License: **[MIT](LICENSE)** for this project's own code & assets. Bundled add-ons under `addons/` keep their own licenses (sky_3d: MIT; Godot OpenXR Vendors: Apache-2.0).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
