-- Stable, secret-free evidence across legacy and Group schemas.
SELECT to_regclass('sl_group') IS NOT NULL AS grouped \gset
\if :grouped
\set QUIET on
CREATE TEMP VIEW snapshot_groups AS SELECT group_id AS business_id FROM sl_group;
\else
\set QUIET on
CREATE TEMP VIEW snapshot_groups AS SELECT scene_id AS business_id FROM sl_scene;
\endif
\set QUIET off
SELECT json_build_object(
 'links',(SELECT COALESCE(json_agg(x ORDER BY x.code),'[]') FROM
   (SELECT code,target_url,scene_id,status,EXTRACT(EPOCH FROM expires_at) AS expires_epoch FROM sl_link) x),
 'business_ids',(SELECT COALESCE(json_agg(business_id ORDER BY business_id),'[]') FROM snapshot_groups),
 'access_keys',(SELECT COALESCE(json_agg(access_key ORDER BY access_key),'[]') FROM sl_tenant_credential),
 'current_max',(SELECT current_max FROM sl_id_sequence WHERE id=1)
);
