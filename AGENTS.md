# Linklet engineering rules

- Follow `openspec/changes/refactor-backend-v02/` and `docs/v02-migration.md`.
- Lua modules live in `lib/linklet`, loaded as `linklet.*`. Repository owns SQL;
  Core uses injected dependencies and never uses ngx, HTTP or SQL directly.
- Tenant grants groups through `group_ids`; links belong only to groups.
- Gateway validates current Host/domain, link status/expiry, never tenant/group status.
- Preserve codes, group business IDs, credentials and the monotonic ID cursor.
- Never modify migration 001 or run destructive migrations on production implicitly.
- Run `make test`, `make lint`, `make acceptance-docker`, and documentation checks.
  Keep the 80% combined source coverage gate. Record limitations honestly.
