"""Flatpak xonshrc: sets up host command forwarding via flatpak-spawn."""

# Add host-spawn symlinks directory to PATH (at the end, so sandbox commands take priority)
with @.env.swap(HOST_CMDS="/app/libexec/host-cmds"):
    if @.imp.os.path.isdir($HOST_CMDS):
        $PATH.append($HOST_CMDS)

# Convenience alias: run any command on the host explicitly
aliases["host"] = lambda args: ![flatpak-spawn --host @(args)]

