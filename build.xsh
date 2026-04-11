#!/usr/bin/env xonsh

import sys
import os
import shutil
import tempfile
import re
from pathlib import Path

try:
    import click
except ImportError:
    print("ERROR: click is required. Install with: pip install click")
    sys.exit(1)

APP_ID      = "io.github.xonsh.xonsh"
MANIFEST    = f"{APP_ID}.yml"
BUNDLE_NAME = "xonsh.flatpak"
RUNTIME_VER = "24.08"
REPO_DIR    = "repo"
BUILD_DIR   = "build-dir"

DEFAULT_GIT_URL = None

def _run(cmd):
    """Run a command, abort on failure."""
    print(f"\n>>> {cmd}\n")
    ret = !([@(cmd.split())])
    if ret.returncode != 0:
        print(f"\nFATAL: command failed (exit {ret.returncode})")
        sys.exit(1)

def _check_cmd(name):
    """Check that a command is available."""
    if !(which @(name) > /dev/null 2>&1).returncode != 0:
        print(f"ERROR: '{name}' not found. Install it first.")
        sys.exit(1)

def _has_runtime(name, ver):
    """Check if a Flatpak runtime/SDK is installed (user)."""
    out = $(flatpak list --user --runtime --columns=application,branch 2>/dev/null)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == name and parts[1] == ver:
            return True
    return False

def _is_9p_fs(path):
    """Check if path is on a 9P filesystem (WSL /mnt/c/)."""
    try:
        out = $(stat -f -c '%T' @(str(path)) 2>/dev/null).strip()
        return out in ('v9fs', '9p')
    except Exception:
        return '/mnt/' in str(path)

def _parse_git_url(url):
    """Parse a git URL into (clone_url, branch).

    Supports:
      https://github.com/owner/repo
      https://github.com/owner/repo/tree/branch
      https://gitlab.com/owner/repo/-/tree/branch
      https://codeberg.org/owner/repo/src/branch/name
      git@github.com:owner/repo.git
      owner/repo  (shorthand, assumes GitHub)
    """
    # Shorthand: owner/repo
    if re.match(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$', url):
        return f'https://github.com/{url}.git', None

    # SSH: git@host:owner/repo.git
    m = re.match(r'^git@([^:]+):(.+?)(?:\.git)?$', url)
    if m:
        return f'https://{m.group(1)}/{m.group(2)}.git', None

    # HTTP(S) URLs
    m = re.match(r'^(https?://[^/]+)/(.+?)(?:\.git)?$', url)
    if not m:
        print(f"ERROR: cannot parse git URL: {url}")
        sys.exit(1)

    host = m.group(1)
    path = m.group(2).rstrip('/')
    parts = path.split('/')

    # GitHub/Codeberg: /owner/repo/tree/branch/name
    # GitLab:          /owner/repo/-/tree/branch/name
    branch = None
    repo_parts = []
    i = 0
    while i < len(parts):
        if parts[i] == '-' and i + 2 < len(parts) and parts[i + 1] == 'tree':
            # GitLab style: /-/tree/branch
            branch = '/'.join(parts[i + 2:])
            break
        elif parts[i] == 'tree' and i >= 2:
            # GitHub/Codeberg style: /tree/branch
            branch = '/'.join(parts[i + 1:])
            break
        elif parts[i] == 'src' and i >= 2 and i + 1 < len(parts) and parts[i + 1] == 'branch':
            # Codeberg style: /src/branch/name
            branch = '/'.join(parts[i + 2:])
            break
        else:
            repo_parts.append(parts[i])
        i += 1

    if not repo_parts:
        repo_parts = parts[:2]

    repo_path = '/'.join(repo_parts)
    clone_url = f'{host}/{repo_path}.git'
    return clone_url, branch

def _patch_manifest(manifest_path, clone_url, branch):
    """Rewrite the git source URL and branch in the manifest."""
    text = manifest_path.read_text()
    text = re.sub(
        r'(url:\s+)\S+\.git',
        rf'\1{clone_url}',
        text,
    )
    text = re.sub(
        r'(branch:\s+)\S+',
        rf'\1{branch or "main"}',
        text,
    )
    # Remove pinned commit if present
    text = re.sub(r'\n\s+commit:\s+\S+', '', text)
    manifest_path.write_text(text)


@click.command()
@click.option('--git-url', default=None,
              help='Git URL: https://github.com/owner/repo/tree/branch or owner/repo. '
                   'If omitted, uses the URL and branch from the manifest.')
@click.option('--output-file', default=BUNDLE_NAME, help=f'Output bundle filename. Default: {BUNDLE_NAME}')
@click.option('--clean', is_flag=True, help='Remove build artifacts before building.')
@click.option('--no-deps', is_flag=True, help='Skip Flatpak runtime installation.')
def main(git_url, output_file, clean, no_deps):
    """Build xonsh Flatpak package from a git repository."""
    srcdir = Path(__file__).resolve().parent
    print(f"Source directory: {srcdir}")

    if git_url:
        clone_url, branch = _parse_git_url(git_url)
        print(f"Xonsh source: {clone_url}" + (f" @ {branch}" if branch else ""))
    else:
        clone_url, branch = None, None
        print("Xonsh source: using manifest defaults")

    if not (srcdir / MANIFEST).exists():
        print(f"ERROR: {MANIFEST} not found in {srcdir}")
        sys.exit(1)

    _check_cmd("flatpak")
    _check_cmd("flatpak-builder")

    if not no_deps:
        print("\n=== Ensuring Flathub remote ===")
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

        for rt in [f"org.freedesktop.Platform/x86_64/{RUNTIME_VER}",
                   f"org.freedesktop.Sdk/x86_64/{RUNTIME_VER}"]:
            name = rt.split("/")[0]
            if _has_runtime(name, RUNTIME_VER):
                print(f"  {rt} — already installed")
            else:
                print(f"\n=== Installing {rt} ===")
                flatpak install --user -y flathub @(rt)
    else:
        print("\n=== Skipping dependency installation (--no-deps) ===")

    if _is_9p_fs(srcdir):
        buildroot = Path(tempfile.mkdtemp(prefix='fp-build-'))
        print(f"\n=== 9P filesystem detected, building in {buildroot} ===")
        # Copy source files
        for f in srcdir.iterdir():
            if f.name in ('.flatpak-builder', BUILD_DIR, REPO_DIR, BUNDLE_NAME):
                continue
            dest = buildroot / f.name
            if f.is_dir():
                shutil.copytree(f, dest)
            else:
                shutil.copy2(f, dest)
        workdir = buildroot
    else:
        workdir = srcdir

    manifest_path = workdir / MANIFEST
    if clone_url:
        _patch_manifest(manifest_path, clone_url, branch)
        print(f"Manifest updated: {clone_url}" + (f" @ {branch}" if branch else ""))

    if clean:
        print("\n=== Cleaning build artifacts ===")
        for d in [BUILD_DIR, REPO_DIR, '.flatpak-builder']:
            p = workdir / d
            if p.exists():
                shutil.rmtree(p)

    print("\n=== Building Flatpak ===")
    cd @(workdir)
    flatpak-builder --user --force-clean --repo=@(REPO_DIR) @(BUILD_DIR) @(MANIFEST)

    if not (workdir / REPO_DIR).exists():
        print("FATAL: build failed — repo directory not created")
        sys.exit(1)

    print(f"\n=== Creating {output_file} ===")
    flatpak build-bundle @(REPO_DIR) @(output_file) @(APP_ID)

    bundle = workdir / output_file
    if not bundle.exists():
        print("FATAL: bundle creation failed")
        sys.exit(1)

    output = srcdir / output_file
    if workdir != srcdir:
        shutil.copy2(bundle, output)
        shutil.rmtree(workdir)
        print(f"Build artifacts cleaned from {workdir}")

    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"\nDone!  {output_file}  ({size_mb:.1f} MB)")
    print(f"\nInstall with:")
    print(f"  flatpak install --user {output_file}")
    print(f"\nRun with:")
    print(f"  flatpak run {APP_ID}")
    print(f"\nUninstall with:")
    print(f"  flatpak uninstall --user {APP_ID}")


if __name__ == '__main__':
    main()
