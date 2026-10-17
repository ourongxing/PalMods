### Version Control

- Use `git` as the primary version control system for this repository.
- Prefer `git` commands and workflows for status checks, history inspection, branches, commits, and pushes.
- Do not use GitHub `github:yeet` skills in this repository.
- Do not create branches or pull requests unless the user explicitly requests
  that exact action. When asked to commit or push without further
  qualification, commit the intended changes and push directly to the current
  branch.
- When asked to "separately push" multiple changes, treat that as separate
  commits pushed sequentially to the current branch, not separate branches or
  pull requests, unless explicitly requested.

### Commit Messages

- All commit messages must follow Conventional Commits: `<type>(<scope>): <summary>`.
- Example: `chore(init): initial import`.

### Development Testing

- Keep the existing local installation workflow during mod development/testing.
  Switch to Workshop deployment when the mod is being prepared for Workshop
  publication; do not migrate all development mods in advance.
- When switching, use the corresponding item folder under
  `G:/SteamLibrary/steamapps/workshop/content/1623730/`. For published mods, use
  the existing PublishedId documented in `docs/WORKSHOP.md`; preserve
  `.workshop.json` and the Workshop package layout.

### Workshop Listings

- Localized `mods/<Mod>/workshop/README.<language>.md` files are the source
  of Workshop listing titles and mod-specific descriptions.
- Shared feedback, log instructions, and source/license text live in
  `tools/workshop/templates/`. The packaging tool appends the localized
  footer to generated listings and packaged READMEs; do not duplicate it in
  individual mod READMEs. UE4SS log instructions apply only to mods depending
  on UE4SSExperimentalPW.
- Do not maintain or package `mods/<Mod>/workshop/README.md` language-index
  files; use the four localized READMEs directly.
- Do not directly edit `listing.json`. Change the corresponding localized
  README files, then regenerate the listings with `tools/package_workshop.py`.
- Run `python tools/package_workshop.py all --listings-only` to generate
  `dist/workshop-listings/<Mod>/listing.json` without building mods. If output
  already exists, use a fresh `--output-root` directory.
- Full Workshop packaging also generates `listing.json` automatically from
  the localized READMEs. Keep generated listings out of the source templates.
