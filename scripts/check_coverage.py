from pathlib import Path
import re

report = Path("luacov.report.out").read_text()
match = re.search(r"^Total\s+\d+\s+\d+\s+(\d+(?:\.\d+)?)%?\s*$", report, re.M)
assert match, "Unable to parse LuaCov total"
coverage = float(match[1])
print(f"Source coverage: {coverage:.2f}% (required: 80%)")
assert coverage >= 80, "Source coverage below 80%"
