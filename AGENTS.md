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

### Workshop Listings

- Localized `mods/<Mod>/workshop/README.<language>.md` files are the only
  source of Workshop listing titles and descriptions.
- Do not directly edit `listing.json`. Change the corresponding localized
  README files, then regenerate the listings with `tools/package_workshop.py`.
- Run `python tools/package_workshop.py all --listings-only` to generate
  `dist/workshop-listings/<Mod>/listing.json` without building mods. If output
  already exists, use a fresh `--output-root` directory.
- Full Workshop packaging also generates `listing.json` automatically from
  the localized READMEs. Keep generated listings out of the source templates.
