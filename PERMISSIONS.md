# Flatpak Permissions Rationale

Xonsh is an interactive shell. Like any shell, it needs broad access to the
system to be useful. Each permission below is explained and justified.

## `--share=network`

Shell commands routinely need network access: `curl`, `wget`, `pip install`,
`git clone`, `ssh`, package managers, and user scripts that fetch data.
A shell without network is crippled for most real-world use.

## `--share=ipc`

Required for X11 shared memory, used by `pyperclip` for clipboard
integration (copy/paste). Without IPC, clipboard operations fail silently.

## `--device=all`

Xonsh needs access to `/dev/tty` and `/dev/pts/*` for terminal operations:
raw mode, job control, signal handling, and pseudo-terminal allocation for
subprocesses. The more restrictive `--device=dri` is insufficient — terminal
devices are not covered by it. `--device=all` is standard for terminal
applications on Flathub.

## `--filesystem=home`

A shell's primary workspace is the user's home directory. Users expect to
`cd ~`, edit dotfiles, run scripts, manage projects, and read/write files
anywhere under `$HOME`. Restricting this to XDG portals would make the shell
unusable for its core purpose.

## `--filesystem=/tmp`

Many shell commands and scripts use `/tmp` for temporary files. The `$TMPDIR`
environment variable conventionally points to `/tmp`. Build tools, compilers,
package managers, and user scripts all expect writable `/tmp`. XDG portals
do not cover this use case — programs call `mktemp` and write to `/tmp`
directly without portal negotiation.

## `--filesystem=host:ro`

Read-only access to the host filesystem allows users to browse and read files
outside their home directory (e.g., `/etc/`, `/var/log/`, `/opt/`). This is
essential for system administration tasks that shells are commonly used for.
The access is read-only — the sandbox still prevents writes outside `$HOME`
and `/tmp`.

Note: this does NOT give access to host executables. Host `/usr/bin` is
shadowed by the Flatpak runtime. Executables are forwarded via
`flatpak-spawn --host` instead (see `--talk-name` below).

## `--talk-name=org.freedesktop.Flatpak`

Enables `flatpak-spawn --host`, which forwards commands to the host system.
The Freedesktop runtime includes ~728 basic Unix commands, but system-specific
tools (`git`, `docker`, `ssh`, `systemctl`, `htop`, etc.) are absent from the
sandbox. Without host command forwarding, users cannot run the vast majority
of commands they expect from a shell.

This is the same pattern used by Distrobox, Toolbox, and other container-based
terminal environments. Symlinks in `/app/libexec/host-cmds/` point to a
`host-spawn` script that calls `flatpak-spawn --host <command>`. These are
appended to `$PATH` (not prepended), so sandbox binaries always take priority.

## `--env=TERM=xterm-256color`

Sets a sane default terminal type. Without this, `$TERM` may be unset or set
to a value that ncurses applications cannot recognize, causing "Error opening
terminal" failures. `xterm-256color` is universally supported and matches the
capabilities of modern terminal emulators.

## `--env=PATH=/app/bin:/usr/bin:/app/libexec/host-cmds`

Appends `/app/libexec/host-cmds` to the standard Flatpak `$PATH`. This
directory contains symlinks for host-forwarded commands (see
`--talk-name` above). Without this, the symlinks exist but are not found by
the shell. `/app/libexec/host-cmds` is placed last so that sandbox binaries
in `/app/bin` and `/usr/bin` always take priority over host-forwarded ones.
