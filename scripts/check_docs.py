from pathlib import Path
import re

required = ["README.md", "docs/api.md", "docs/development.md", "docs/deployment.md", "docs/acceptance.md"]
for name in required:
    assert Path(name).is_file(), f"Missing documentation: {name}"
for document in [Path("README.md"), *Path("docs").glob("*.md")]:
    for target in re.findall(r"\]\(([^)]+)\)", document.read_text()):
        if "://" in target or target.startswith("#"):
            continue
        target = target.split("#")[0]
        if target:
            assert (document.parent / target).exists(), f"Broken link in {document}: {target}"
print("Documentation files and local links verified")
