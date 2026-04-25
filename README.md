# Rotor

> Desktop-first, open-source 2FA client. Keep your TOTP codes on the screen you actually work on, not stuck in your phone.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](#)

🇨🇳 [中文 README](README.zh-CN.md)

---

## Why Rotor

Most TOTP apps live on your phone. When you're typing a 2FA code into a desktop login flow, that means: pick up phone → unlock phone → open authenticator → squint at six digits → type. Rotor flips that around — your codes live in the macOS menu bar, one click away.

**Differentiators:**

- **Menu-bar resident** on macOS: click the icon, popover gives you all your codes (Raycast / Stats / Raivo OTP–style interaction)
- **Always-on-top toggle** for both the main window and the popover
- **Compatible import / export** with Google Authenticator, Aegis, and 2FAS
- **Local-only**: no cloud, no account system, no telemetry

---

## Features

### Implemented (MVP)

- Add accounts via paste `otpauth://` URI **or** drop in QR code images (multi-select supported)
- TOTP display with 30s countdown ring, 3+3 grouped Courier Prime digits
- Click to copy, clipboard auto-clears after 60 seconds (with hash check so it won't overwrite something else you just copied)
- Menu-bar status icon (template image, dark-mode aware) with left-click popover and right-click menu
- Edit / delete accounts, manual drag-to-reorder, grouping, search, sort by name / recent / custom
- Always-on-top toggle (main window and popover, independent)
- Encrypted local export / import (`.rotor` format, **Argon2id** + AES-256-GCM, backwards-compatible with PBKDF2 v1 backups)
- Third-party imports:
  - Google Authenticator `otpauth-migration://` QR (protobuf decoded in-app)
  - Aegis JSON (unencrypted)
  - 2FAS JSON (unencrypted)
- Optional **Protection mode**: master password derives a KEK via Argon2id, AES-GCM wraps the on-disk vault key, configurable idle auto-lock (1 / 5 / 15 / 60 min)
- Screen recording / screenshot blocking (`NSWindow.sharingType = .none`)
- Light/dark mode follows system

### Coming later

- HOTP / Steam Guard
- iCloud sync
- Browser extension companion
- Mobile clients

---

## Install

### From a Release

1. Grab the DMG matching your Mac from the [Releases](../../releases) page:
   - Apple Silicon → `Rotor-<version>-apple-silicon.dmg`
   - Intel → `Rotor-<version>-intel.dmg`
2. Open the DMG, drag Rotor.app into Applications.
3. **First launch:** because the build is currently ad-hoc signed, macOS Gatekeeper will warn you. Right-click Rotor.app → "Open" → "Open" once. Subsequent launches work normally.

### From source

```bash
git clone https://github.com/deskotp/rotor.git
cd rotor
open rotor.xcodeproj
# Select the "rotor" scheme, then ⌘R
```

Requirements:

- macOS 26 (Tahoe) or newer
- Xcode 26 or newer (project deployment target = `26.3`)

---

## Storage and security

### File layout

Rotor's data lives in the App Sandbox container at:

```
~/Library/Containers/com.liasica.rotor/Data/Library/Application Support/
├── default.store           # SwiftData (account metadata, ciphertexts)
├── default.store-shm
├── default.store-wal
├── vault.key               # 32-byte random vault key, when protection is OFF
└── vault.master            # JSON envelope, when protection is ON
```

### Protection OFF (default)

- `vault.key` is a 32-byte random AES-256 key, file mode `0600`
- TOTP secrets are AES-GCM encrypted with this key and stored in `default.store`
- An attacker with disk access still has to grab two files; obfuscation only

### Protection ON

- `vault.master` is a JSON envelope:
  ```json
  {
    "version": 1,
    "kdf":     { "name": "argon2id", "salt": "<base64>", "opsLimit": 3, "memLimit": 67108864 },
    "nonce":   "<base64>",
    "ciphertext": "<base64>"
  }
  ```
- User master password → **Argon2id** (64 MiB / 3 rounds, RFC 9106 v1.3) → 256-bit KEK
- KEK + AES-256-GCM → wraps the 32-byte vault key
- Master password is **never** persisted; vault key lives only in memory and is wiped when the vault locks
- Lose the master password → no recovery path. Keep it safe

### Backups (`.rotor` files)

- Same envelope shape as `vault.master`; `version: 2` uses Argon2id, `version: 1` (legacy export) uses PBKDF2-SHA256 with 600,000 iterations, both decode-compatible
- Imports re-encrypt every secret with the destination machine's vault key

### Backup compatibility

Rotor can import:
- Its own `.rotor` files (v1 PBKDF2 / v2 Argon2id)
- Google Authenticator `otpauth-migration://` payloads (zero-dependency in-house protobuf parser)
- Aegis JSON (unencrypted)
- 2FAS JSON (unencrypted)

Encrypted Aegis / 2FAS backups must be decrypted in their original app first.

---

## Development

### Project layout

```
rotor/
├── Core/                     # Domain logic (TOTP, vault, importers, services)
├── Design/                   # Theme tokens (color, font)
├── Views/                    # SwiftUI views
├── Vendor/Reorderable/       # Vendored visfitness/Reorderable, patched for macOS
├── Fonts/                    # Bundled Courier Prime (OFL)
├── Assets.xcassets/          # App icon, accent, menu bar icon
└── rotorApp.swift            # App entry point
.design/                       # Design source mirrors (icons, marks, sketch exports)
.github/workflows/release.yml # CI: build + DMG for both arm64 and x86_64
```

### Conventions

- All commit messages and source comments are in **English** (CLAUDE.md §6.1).
- User-facing UI strings stay in Chinese (the project's primary audience). Localization to English is a later milestone.
- Conventional Commits: `feat: …`, `fix: …`, `refactor: …`, `docs: …`, `chore: …`, `perf: …`, `ci: …`.
- `master` is always shippable; feature work happens on `feat/xxx` branches.

### Releases

Push a tag matching `v*`, the GitHub Actions workflow builds Rotor for both architectures and publishes a Release with both DMGs.

```bash
git tag v0.1.0
git push origin v0.1.0
```

---

## License

GPL-3.0. See [LICENSE](LICENSE).

The vendored fonts ([Courier Prime](https://github.com/quoteunquoteapps/CourierPrime)) are licensed under the SIL Open Font License — see `rotor/Fonts/OFL.txt`.

---

## Acknowledgements

- [visfitness/Reorderable](https://github.com/visfitness/reorderable) — drag-and-drop reorder primitives (vendored and patched for macOS)
- [jedisct1/swift-sodium](https://github.com/jedisct1/swift-sodium) — Argon2id and friends
- The TOTP / OTP standards: [RFC 6238](https://datatracker.ietf.org/doc/html/rfc6238), [RFC 4226](https://datatracker.ietf.org/doc/html/rfc4226)
- Argon2id parameters per [RFC 9106](https://datatracker.ietf.org/doc/html/rfc9106) and OWASP Password Storage Cheat Sheet
