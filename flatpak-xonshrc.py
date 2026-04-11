"""Flatpak xonshrc: sets up host command forwarding via flatpak-spawn."""
import os

# Add host-spawn symlinks directory to PATH (at the end, so sandbox commands take priority)
_host_cmds = "/app/libexec/host-cmds"
if os.path.isdir(_host_cmds):
    $PATH.append(_host_cmds)

# Convenience alias: run any command on the host explicitly
aliases["host"] = lambda args: ![flatpak-spawn --host @(args)]

del _host_cmds
