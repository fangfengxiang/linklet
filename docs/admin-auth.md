# Admin 安全边界与浏览器接入方案

`/api/v1/shorten/*` 面向租户服务，继续使用 AK/SK HMAC，验证 Credential、Tenant 状态和当前 group_ids 授权。SK 只存储在租户服务端，签名覆盖实际 URI、时间戳和原始请求体。

`/api/v1/admin/*` 是内部平台管理接口，默认 Nginx 仅允许 loopback。它可创建租户、变更授权并签发凭证，不使用租户身份代替管理员身份。生产可配置受控运维网络，但不能将整个管理路径公开到互联网。AK/SK 无法替代这里的内部网络边界；反向代理必须在入口继续执行访问限制，不能让全部公网请求以可信代理地址通过白名单。只开放 Gateway 时，在入口移除两个 API location；Admin API 部署则只路由 API 和健康检查，二者可独立部署并共享 PostgreSQL。

独立 `linklet-admin` 浏览器界面使用后续单独设计的会话认证。建议由服务端 BFF 接入组织身份提供者：浏览器取得 HttpOnly、Secure、SameSite 会话 cookie，服务端验证会话、管理员权限及写请求 CSRF，再从受控网络调用管理 API。凭证签发、授权调整及停用应记录操作者和结果；登出、过期和撤权使会话失效。

当前版本没有实现上述浏览器登录、BFF 或会话接口。现有 credential/create 返回的一次性 SK 面向受控的服务端运维调用；不能由 React 页面直接调用，也不能把租户 SK 写入前端环境变量、localStorage、页面状态或日志。浏览器管理界面应另行定义服务端凭证交付流程。
