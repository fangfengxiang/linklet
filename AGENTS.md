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

## OpenResty architecture references

- When designing or changing OpenResty code, selectively learn from Kong Gateway,
  Apache APISIX, Lapis, and OpenResty's lua-resty-core.
- Prioritize Kong for Lua module namespaces, Admin API/request-processing boundaries,
  database access organization, and integration with the Nginx runtime.
- Reference APISIX for Lua-native functional modules and clear Admin/data-plane
  responsibilities; reference Lapis for lightweight routing, request handling,
  application composition, and PostgreSQL access.
- Reference lua-resty-core for `lib/` layout, Lua namespaces, `require` conventions,
  and OpenResty lifecycle practices, rather than business-domain structure.
- Adapt ideas to Linklet's lightweight short-link scope. Keep explicit dependency
  injection and the existing Core/Repository boundaries; introduce abstractions only
  for concrete needs. These references do not imply adopting a framework, plugin
  system, generic rule engine, DI container, or additional Service/DAO/Provider layers.
