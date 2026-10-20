-- Stable, secret-free evidence across old/expanded/switched schemas.
SELECT json_build_object(
 'links',(SELECT COALESCE(json_agg(x ORDER BY x.code),'[]') FROM
   (SELECT code,target_url,scene_id,status,EXTRACT(EPOCH FROM expires_at) AS expires_epoch FROM sl_link) x),
 'scene_ids',(SELECT COALESCE(json_agg(scene_id ORDER BY scene_id),'[]') FROM sl_scene),
 'access_keys',(SELECT COALESCE(json_agg(access_key ORDER BY access_key),'[]') FROM sl_tenant_credential),
 'current_max',(SELECT current_max FROM sl_id_sequence WHERE id=1)
);
