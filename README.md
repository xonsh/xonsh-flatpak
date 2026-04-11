# Xonsh Flatpak

Flatpak package for [xonsh](https://xon.sh/) — a modern, full-featured and cross-platform Python-based shell.

Built on `org.freedesktop.Platform` / `org.freedesktop.Sdk` 24.08 (Python 3.12).

## Quick Start

```bash
# Build
pip install .          # install build script dependencies (xonsh, click)
xonsh build.xsh        # build from xonsh/xonsh main branch

# Install & run
flatpak install --user xonsh.flatpak
flatpak run io.github.xonsh.xonsh

# Uninstall
flatpak uninstall --user io.github.xonsh.xonsh
```

## Build Options

```bash
# Default: xonsh/xonsh @ main
xonsh build.xsh

# Custom repo and branch
xonsh build.xsh --git-url https://github.com/anki-code/xonsh/tree/anki_new_start

# Custom output filename
xonsh build.xsh --output-file my-xonsh.flatpak

# Clean build (remove cached artifacts)
xonsh build.xsh --clean

# Skip Flatpak runtime installation
xonsh build.xsh --no-deps
```

The `--git-url` flag accepts GitHub, GitLab, Codeberg URLs with branch in the path,
SSH URLs (`git@github.com:owner/repo.git`), or shorthand (`owner/repo`).

### Prerequisites

```bash
sudo apt-get install -y flatpak flatpak-builder
```

The build script automatically installs the Flathub remote and Freedesktop runtime/SDK.

WSL note: The build script detects 9P filesystems (`/mnt/c/`) and automatically
builds in `/tmp/` to avoid FUSE compatibility issues.

## Host Command Forwarding

The Freedesktop runtime includes ~728 standard Unix commands (`ls`, `cat`,
`grep`, `curl`, etc.), but system-specific tools like `git`, `docker`, `ssh`
are not available inside the Flatpak sandbox.

### How it works

```
User types "git status"
  → xonsh finds /app/libexec/host-cmds/git (symlink → host-spawn)
    → host-spawn runs: flatpak-spawn --host --env=TERM=... git status
      → flatpak-spawn executes "git status" on the host system
        → output flows back to xonsh inside the sandbox
```

**`host-spawn`** is a single 2-line shell script:

```sh
#!/bin/sh
exec flatpak-spawn --host --env=TERM="${TERM:-xterm-256color}" "$(basename "$0")" "$@"
```

It uses `basename "$0"` to determine which command to run — so the same script
works for every command via symlinks. `$TERM` is forwarded so that ncurses
applications (`htop`, `vim`, `nano`, etc.) work correctly on the host.

During the Flatpak build, symlinks are created for common host commands:

```
/app/libexec/host-cmds/git    → /app/libexec/host-spawn
/app/libexec/host-cmds/docker → /app/libexec/host-spawn
/app/libexec/host-cmds/ssh    → /app/libexec/host-spawn
/app/libexec/host-cmds/htop   → /app/libexec/host-spawn
...
```

The directory `/app/libexec/host-cmds` is **appended** to `$PATH` (not
prepended), so sandbox binaries in `/app/bin` and `/usr/bin` always take
priority over host-forwarded ones.

### Pre-configured commands

`git`, `docker`, `ssh`, `vim`, `htop`, and many more (~45 total).
To see the full list or add more, edit the `for cmd in ...` loop in
`io.github.xonsh.xonsh.yml`.

### Running other host commands

For commands without a symlink, use `flatpak-spawn` directly:

```bash
flatpak-spawn --host mycommand --flag
```

Or copy `flatpak-xonshrc.py` to `~/.config/xonsh/rc.d/` for the `host` alias:

```xonsh
host mycommand --flag
```

## Sandbox Permissions

| Permission                            | Reason                                        |
|---------------------------------------|-----------------------------------------------|
| `--share=network`                     | Network access for shell commands              |
| `--share=ipc`                         | IPC for clipboard (pyperclip)                  |
| `--device=all`                        | Full device access for terminal operations     |
| `--filesystem=home`                   | Read/write access to user home directory       |
| `--filesystem=/tmp`                   | Access to /tmp for temp files                  |
| `--filesystem=host:ro`                | Read-only access to host filesystem            |
| `--talk-name=org.freedesktop.Flatpak` | D-Bus access for `flatpak-spawn --host`        |

## License

xonsh is licensed under the BSD-2-Clause license.
