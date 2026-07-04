# brag-for-cursor

```
███████╗ ███████╗  █████╗  ███████╗
██╔══██╗██╔══██╗██╔══██╗██╔════╝
██████╔╝██████╔╝███████║██║  ███╗   for Cursor, on macOS
██╔══██╗██╔══██╗██╔══██║██║   ██║
██████╔╝██║  ██║██║  ██║╚██████╔╝
╚═════╝ ╚═════╝█║  ██╝ ╚═════╝
```

**You built it. Now let Cursor brag about it.**

One shell script, zero manual setup: installs [`/brag`](https://github.com/latent-spaces/brag) — the skill that turns any project into a short, polished, shareable launch video — into [Cursor](https://cursor.com), plus every dependency it needs (Node 22+, FFmpeg, and the Hyperframes companion skills). Also fully uninstalls itself when you're done.

![macOS](https://img.shields.io/badge/platform-macOS-black?logo=apple)
![bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Cursor](https://img.shields.io/badge/editor-Cursor-6C5CE7)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Why this exists

[`/brag`](https://github.com/latent-spaces/brag) ships as a Claude Code skill. Cursor (2.4+) speaks the same open [Agent Skills](https://cursor.com/docs/skills) standard, so it *can* run `/brag` too — but there's no built-in installer for that path, and getting all the pieces (Node, FFmpeg, the skill itself, and its Hyperframes companion skills) lined up by hand is exactly the kind of yak-shave that a tool about *shipping fast* shouldn't require.

`brag-cursor.sh` does the whole thing in one run, with a CLI that doesn't look like it was thrown together in five minutes — and a matching uninstaller for when you want it gone.

## What it actually does

**Install:**

1. Checks/installs prerequisites — Xcode Command Line Tools, Homebrew, Node.js 22+, FFmpeg.
2. Lets you pick a target:
   - **Project** → `<project>/.cursor/skills/` (this repo only)
   - **Global** → `~/.cursor/skills/` (every Cursor project on the machine)
   - **Both**
3. Clones [`latent-spaces/brag`](https://github.com/latent-spaces/brag) and installs the `/brag` skill to your chosen target(s).
4. Installs the Hyperframes companion skills — a hard dependency of `/brag`'s hand-off step — via `npx hyperframes skills update`, then mirrors the relevant packages into `~/.cursor/skills` (and into the project, if a project target was chosen). See [*the bug we found*](#the-bug-we-found-and-fixed-along-the-way) below for why this isn't a one-liner.
5. Drops a `.cursor/rules/brag.mdc` fallback for Cursor versions predating native Skills support (< 2.4).
6. Warms up headless Chrome and runs `hyperframes doctor` so you know the environment is actually ready before you ever type `/brag`.
7. Offers `uv` (optional — only improves beat-sync precision if you bring your own music track; the built-in fallback works fine without it).
8. Offers to store a HeyGen API key (optional — local rendering needs none).

**Uninstall:** removes `/brag` (and, on request, the Hyperframes companion packages) from whichever target(s) you pick, plus the `.cursor/rules/brag.mdc` fallback — with a clear per-item report of what was actually found and removed. Homebrew, Node, FFmpeg, and `uv` are never touched; those belong to your machine, not to this script.

## Install

```bash
git clone https://github.com/clezcoding/brag-for-cursor.git
cd brag-for-cursor
chmod +x brag-cursor.sh
./brag-cursor.sh
```

That last command drops you into an interactive menu (install or uninstall, then which target). Prefer to skip straight to the point:

```bash
./brag-cursor.sh install --project              # this project, current directory
./brag-cursor.sh install --project /path/to/app  # this project, specific directory
./brag-cursor.sh install --global                # every Cursor project on this machine
./brag-cursor.sh install --both /path/to/app     # both at once
./brag-cursor.sh install -y                      # no prompts (defaults to --project, cwd)
```

Once it's done, open the project in Cursor and type:

```
let's /brag
```

or steer the tone:

```
/brag --tone chaotic
```

## Uninstall

```bash
./brag-cursor.sh uninstall                          # interactive menu
./brag-cursor.sh uninstall --project
./brag-cursor.sh uninstall --global
./brag-cursor.sh uninstall --both /path/to/app
./brag-cursor.sh uninstall --both --purge -y        # remove everything, no prompts
```

By default it only ever removes `/brag` itself and the `.cursor/rules/brag.mdc` fallback from the target(s) you pick, and it asks before touching anything shared. Two things it will always ask about first (unless you pass `-y`, which answers "no" to both):

- **Hyperframes companion packages** — shared with other tools that might use them; pass `--purge` to remove them too without asking.
- **`~/.heygen/credentials`** — shared with the standalone `heygen` CLI, if you have it installed; asked separately every time, regardless of `--purge`.

## All options

| Flag | Effect |
|---|---|
| `install` \| `uninstall` | Mode. Default: `install`. |
| `--project [DIR]` | Target: this project (default directory: cwd) |
| `--global` | Target: global (`~/.cursor/skills`) |
| `--both [DIR]` | Both targets at once |
| `--purge` | *(uninstall)* also remove the Hyperframes companion skills, no confirmation |
| `--heygen-key KEY` | *(install)* store a HeyGen API key non-interactively |
| `-y`, `--yes` | No prompts at all |
| `-h`, `--help` | Show help |

Safe to run more than once: install is idempotent, uninstall only ever touches what this script itself placed (or, with `--purge`, the Hyperframes packages it manages).

## The bug we found (and fixed) along the way

The public Hyperframes CLI docs list `--claude` / `--cursor` / `--codex` / `--gemini` flags for `hyperframes skills`, implying you can target a specific tool or even a specific project directory. Cloning [`heygen-com/hyperframes`](https://github.com/heygen-com/hyperframes) and reading the actual source (`packages/cli/src/commands/skills.ts`) told a different story: those flags don't exist anymore. The command always installs **globally**, writing real files to `~/.claude/skills` and `~/.agents/skills`, then best-effort mirrors them (as symlinks) into every *other* installed agent's global directory — including `~/.cursor/skills`, but **only if `~/.cursor` already exists** (i.e. Cursor has been opened at least once).

There is no project-scoped install path in the Hyperframes CLI itself. So this script:

- Always runs `npx hyperframes skills update` once, globally (there's no alternative).
- Explicitly copies the relevant packages (`hyperframes`, `hyperframes-*`, `general-video` — filtered out of the ~20 skills the CLI installs, to skip unrelated ones like `figma` or `motion-graphics`) into `~/.cursor/skills`, regardless of whether Cursor's own mirroring already ran.
- For a **project** target, copies the same filtered set into the project's `.cursor/skills/` too, so the project is self-contained and doesn't depend on install order or a global side effect.

Every step above was verified against a real `npx hyperframes doctor` / `npx hyperframes skills update` run and the upstream source, not just the documentation — the docs page is stale, the source code isn't.

## Requirements

Installed automatically if missing:

- macOS (Xcode Command Line Tools, Homebrew)
- Node.js 22+
- FFmpeg
- Cursor 2.4+ recommended (native Agent Skills support) — earlier versions fall back to the bundled `.cursor/rules/brag.mdc`

## Troubleshooting

- **`hyperframes doctor` flags Chrome as missing** — run `npx hyperframes browser ensure` (the script already does this, but first-run downloads can be slow on a fresh machine).
- **Hyperframes skills install fails with a GitHub rate-limit message** — run `gh auth login`, or set a `GITHUB_TOKEN` in your environment, then re-run.
- **Want richer beat-sync on your own music track instead of the bundled tracks?** — install `uv` (the script offers this) so `/brag` can run its extended music-cue analysis; without it, `/brag` automatically falls back to `npx hyperframes beats`.

## Credits

- [`latent-spaces/brag`](https://github.com/latent-spaces/brag) — the skill this installs.
- [`heygen-com/hyperframes`](https://github.com/heygen-com/hyperframes) — the video composition engine `/brag` hands off to.
- [Cursor Agent Skills](https://cursor.com/docs/skills) — the open standard that makes any of this possible outside of Claude Code.

This is an independent, unofficial helper script — not affiliated with latent-spaces, HeyGen, or Cursor.

## License

MIT — see [LICENSE](LICENSE).
