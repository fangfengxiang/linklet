local _M = {}
local json = require("cjson.safe")
local port = tonumber(os.getenv("LINKLET_TEST_PGPORT")) or 15432
local key = string.rep("ab",32)
_M.ak = "acceptance-ak"
_M.sk = "acceptance-secret-key-32-characters"
function _M.db()
    return require("linklet.db.postgres").new({host="127.0.0.1",port=port,database="linklet_test",user="linklet",password="acceptance_only"})
end
function _M.setup()
    local app = require("linklet.app")
    local deps = app.init({database={host="127.0.0.1",port=port,database="linklet_test",user="linklet",password="acceptance_only"},encryption_key=key,segment_size=2})
    _M.deps = deps
    deps.cache.sync_window = nil
    assert(deps.db:query("TRUNCATE sl_short_link, sl_group_config, sl_group, sl_domain_entry, sl_tenant_credential, sl_tenant RESTART IDENTITY CASCADE"))
    -- Codes are reused only by this disposable fixture. Keep revisions monotonic
    -- so long-running runtime containers cannot mistake a reset for fresh data.
    assert(deps.db:transaction(function(conn)
        local row=assert(conn:query("SELECT cache_revision FROM sl_id_sequence WHERE sequence_key=1 FOR UPDATE"))[1]
        local revision=row and tonumber(row.cache_revision)+1 or 1
        assert(conn:query("TRUNCATE sl_id_sequence"))
        assert(conn:query("INSERT INTO sl_id_sequence(sequence_key,current_max,cache_revision) VALUES(1,0,$1)",revision))
        return true
    end))
    assert(deps.db:query("INSERT INTO sl_tenant (id,name) VALUES (1,'tenant-one'),(2,'tenant-two')"))
    assert(deps.db:query("INSERT INTO sl_domain_entry (id,domain,status) VALUES (1,'s.example.com',2),(2,'other.example.com',2)"))
    assert(deps.db:query("INSERT INTO sl_group (group_id,tenant_id,name,domain_entry_id) VALUES (1,1,'group-one',1),(2,2,'group-two',2)"))
    assert(deps.tenant_model:grant(1,{1}))
    assert(deps.tenant_model:grant(2,{2}))
    assert(deps.db:query("SELECT setval('sl_tenant_id_seq',2), setval('sl_domain_entry_id_seq',2), setval('sl_group_group_id_seq',2)"))
    assert(deps.credential_model:create(1,_M.ak,_M.sk))
    assert(deps.credential_model:create(2,'other-ak',_M.sk))
    ngx.shared.linklet_cache:flush_all()
    return deps
end
function _M.request(method, uri, body, opts)
    opts = opts or {}
    body = body or ""
    local timestamp = opts.timestamp or tostring(ngx.time())
    local signature = ngx.encode_base64(ngx.hmac_sha1(_M.sk, method .. "\n" .. (opts.signed_uri or uri) .. "\n" .. timestamp .. "\n" .. (opts.signed_body or body)))
    local headers = {"Host: " .. (opts.request_host or "s.example.com"), "Connection: close", "Content-Type: application/json", "Content-Length: " .. #body}
    if not opts.no_auth then
        headers[#headers+1] = "X-Access-Key: " .. (opts.ak or _M.ak)
        headers[#headers+1] = "X-Signature: " .. (opts.signature or signature)
        if not opts.no_timestamp then headers[#headers+1] = "X-Timestamp: " .. timestamp end
    end
    local socket = ngx.socket.tcp()
    socket:settimeout(10000)
    assert(socket:connect(opts.host or "127.0.0.1", opts.port or tonumber(ngx.var.server_port)))
    assert(socket:send(method .. " " .. uri .. " HTTP/1.0\r\n" .. table.concat(headers,"\r\n") .. "\r\n\r\n" .. body))
    local raw = assert(socket:receive("*a"))
    socket:close()
    local status = tonumber(raw:match("^HTTP/%S+ (%d+)"))
    local head, result = raw:match("^(.-)\r\n\r\n(.*)$")
    return status, json.decode(result), head, result
end
function _M.create(params, opts)
    local status, body = _M.request("POST","/api/v1/shorten/create",json.encode(params or {target_url="https://example.com/page",group_id=1}),opts)
    assert(status == 200, "create status " .. status .. ": " .. json.encode(body))
    return body.data.code
end
return _M
