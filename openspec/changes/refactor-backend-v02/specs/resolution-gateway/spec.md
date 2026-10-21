## MODIFIED Requirements
### Requirement: Effective link resolution
Gateway SHALL 根据请求 Host+Code、短链启用状态、expires_at、当前 DomainEntry 状态判定是否跳转；Tenant/Group 停用 SHALL NOT 使既有有效短链失效。
#### Scenario: Disabled group but active link
- **GIVEN** Group 停用但 ShortLink 启用、未过期且域名投产
- **WHEN** 请求匹配 Host+Code
- **THEN** Gateway SHALL 返回 302
#### Scenario: Host mismatch
- **GIVEN** 短链 Group 当前绑定 domain-a
- **WHEN** 请求使用 domain-b 和同一 code
- **THEN** Gateway SHALL NOT 重定向到目标地址
### Requirement: Unified cached resolution
缓存命中与数据库命中 SHALL 返回一致的解析结果，再统一由 Redirect 输出；缓存 SHALL 不直接发送 302。
#### Scenario: Disabled link invalidation
- **GIVEN** 某 code 已缓存
- **WHEN** 管理接口停用它并完成失效传播
- **THEN** 后续解析 SHALL 不再跳转
