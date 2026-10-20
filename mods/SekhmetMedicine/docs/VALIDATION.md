# Validation

- Workshop 1.0.0 published on 2026-10-20 as 3823292428. Four localized listings, public visibility, tags and both dependencies read back; all 8 downloaded package file hashes matched the release manifest. Subscribed and enabled locally, manual installation archived while the game was stopped. No in-game behavior validation is implied by publishing or download checks; user retains in-game testing.

## 2026-10-20

- Offline: extracted current installed `Pal-Windows.pak` character table. Both `Sekhmet` and `BOSS_Sekhmet` have Medicine 0, Handiwork 6, Mining 3, Transporting 2. Final patch changes only `BOSS_Sekhmet` Medicine to 3; normal `Sekhmet` is omitted and keeps vanilla values.
- Offline: current game contains `AM_Sekhmet_CommonWork` and a `CommonWork` action entry in `BP_Sekhmet`. Asset presence alone does not prove medicine production works.
- Research evidence: `.build/SekhmetMedicine/parameters.json`, `character.json`, `animation.json`, `assets.txt`. Extracted game resources remain outside source control.
- Real UI: pending. Must check actual medicine output, continuing work, leaving work, food/sleep, and preserved original jobs. Book enhancement, multiplayer and dedicated server are unverified.
- Build/package passed; local installation completed with game processes absent, and installed files matched build hashes.
- Startup attempts through the existing game executables exposed no game window; no new PalSchema loading evidence was obtained. User requested to perform in-game testing personally, so further launch/UI work stopped.
- Shared tooling regression: 28/29 passed. Existing Workshop package version assertion expects 1.0.0 but sees 1.0.1 (`test_workshop.py:169`); unrelated to this patch, left unchanged.
- User narrowed scope to BOSS only. Rebuilt and reinstalled with game processes absent; installer verified final file hashes. In-game verification remains with the user.
- Previously requested base Medicine rank was 5 for BOSS_Sekhmet only. Build and installation hash verification passed with game processes absent; user handles in-game testing.
- Final requested base Medicine rank is 3 for BOSS_Sekhmet only. Build and installation hash verification passed with game processes absent; in-game testing remains with the user.
