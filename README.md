<p align="center">
<img src="./xonsh-flatpak-icon.png" alt="Xonsh Flatpak" width="100px">
</p>

# Xonsh Flatpak
Flatpak package for [xonsh](https://xon.sh/).

## Install and Run

```xsh
# Install flatpak e.g. `sudo apt-get install -y flatpak`
# Download xonsh flatpak
wget https://github.com/xonsh/xonsh-flatpak/releases/latest/download/xonsh.flatpak
flatpak install --user xonsh.flatpak
flatpak run io.github.xonsh.xonsh
```

## Usage

### `host` alias

The Freedesktop runtime includes ~728 standard Unix commands (`ls`, `cat`,
`grep`, `curl`, etc.), but system-specific tools like `git`, `docker`, `ssh`
are not available inside the Flatpak sandbox.

To solve this we have `host` alias in xonsh RC `flatpak.xsh`. It executes 
the command on the host system e.g.

```xsh
host git status  # `flatpak-spawn --host git status`
```

### Symlinks to popular tools

In `io.github.xonsh.xonsh.yml` we have a list of popular commands
(`git`, `docker`, `ssh`, `vim`, `htop`, etc). During the Flatpak build, 
symlinks are created for popular host commands e.g. 
`/app/libexec/host-cmds/git` will be the symlink to `/app/libexec/host-spawn`.

The directory `/app/libexec/host-cmds` is appended to `$PATH` with low priority.


## Build

```bash
sudo apt-get install -y flatpak flatpak-builder
pip install .
xonsh build.xsh  # or with GitHub/GitLab/Codeberg URL: `--git-url https://github.com/xonsh/xonsh/tree/another_branch_name`
flatpak install --user xonsh.flatpak
flatpak run io.github.xonsh.xonsh
```

## See also

* [Flatpak Submission](https://docs.flathub.org/docs/for-app-authors/submission)
* [xonsh AppImage](https://xon.sh/appimage.html)
