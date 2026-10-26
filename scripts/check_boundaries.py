"""Enforce SDD dependency direction without requiring OpenResty."""
from pathlib import Path
import re

root = Path('lib/linklet')
for path in root.rglob('*.lua'):
    layer = path.relative_to(root).parts[0]
    source = path.read_text()
    requires = re.findall(r'require\s*\(?\s*[\"\']([^\"\']+)', source)
    if layer == 'core':
        assert all(name.startswith('linklet.core.') or name == 'slds' or name.startswith('slds.') for name in requires), f'{path}: Core imports infrastructure'
        assert not re.search(r'\bngx\s*[.\[]|\b(?:SELECT|INSERT|UPDATE|DELETE)\b',
                             re.sub(r'--[^\n]*', '', source)), f'{path}: Core contains transport/SQL access'
    if layer not in ('repository', 'db'):
        clean = re.sub(r'--[^\n]*', '', source)
        assert not re.search(r'\b(?:SELECT\s+.+?\s+FROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b',
                             clean, re.S), f'{path}: SQL must stay inside Repository/DB'
    if layer in ('admin', 'gateway'):
        opposite = 'gateway' if layer == 'admin' else 'admin'
        assert not any(name.startswith(f'linklet.{opposite}.') for name in requires), f'{path}: cross-adapter import'
print('Core/Repository and Admin/Gateway dependency boundaries verified')
