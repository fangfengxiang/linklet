"""Validate publishable documentation, including clean-checkout availability."""
from pathlib import Path
import re
import subprocess

try:
    tracked = set(subprocess.check_output(
        ["git", "ls-files", "-z"], stderr=subprocess.DEVNULL
    ).decode().split("\0"))
except (FileNotFoundError, subprocess.CalledProcessError):
    tracked = None  # Source archives and acceptance images do not contain .git.

required = ["README.md", "docs/api.md", "docs/development.md", "docs/deployment.md", "docs/acceptance.md"]
for name in required:
    assert Path(name).is_file(), f"Missing documentation: {name}"
    if tracked is not None:
        assert name in tracked, f"Required documentation is not tracked: {name}"

root = Path.cwd().resolve()
for document in [Path("README.md"), *sorted(Path("docs").glob("*.md"))]:
    if tracked is not None and document.as_posix() not in tracked:
        continue  # Personal notes are outside the publishable documentation set.
    for target in re.findall(r"\]\(([^)]+)\)", document.read_text()):
        if "://" in target or target.startswith("#"):
            continue
        target = target.split("#")[0]
        if not target:
            continue
        resolved = (document.parent / target).resolve()
        assert resolved.exists(), f"Broken link in {document}: {target}"
        if tracked is not None:
            relative = resolved.relative_to(root).as_posix()
            available = relative in tracked or (
                resolved.is_dir() and any(name.startswith(relative + "/") for name in tracked)
            )
            assert available, f"Link target unavailable in clean checkout: {document}: {target}"
print("Documentation files and publishable local links verified")
