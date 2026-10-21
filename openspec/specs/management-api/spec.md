# management-api Specification

## Purpose

Create, generate and disable short links within the authenticated tenant boundary.

## Requirements

### Requirement: Create short link

The system SHALL provide a POST endpoint to create a short link.

#### Scenario: Create with valid parameters

- **GIVEN** an authenticated request with target_url and group_id
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the system SHALL generate a short code
- **AND** the system SHALL persist the link record to PostgreSQL
- **AND** the response SHALL include the generated code
- **AND** the response SHALL have status code 200 with JSON body {code:0, message:"success", data:{code:"xxx"}}

#### Scenario: Missing target_url

- **GIVEN** a request without target_url
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the response SHALL have status code 400 with error message

#### Scenario: Invalid group_id

- **GIVEN** a request with a group_id that is not authorized for the authenticated tenant
- **WHEN** POST /api/v1/shorten/create is called
- **THEN** the response SHALL have status code 403 with error message

### Requirement: Generate short link with URL

The system SHALL provide a POST endpoint to create a short link and return the full short URL.

#### Scenario: Generate with valid parameters

- **GIVEN** an authenticated request with target_url and group_id
- **WHEN** POST /api/v1/shorten/gen is called
- **THEN** the system SHALL create the link (same as /api/v1/shorten/create)
- **AND** the system SHALL resolve the group's domain entry
- **AND** the response SHALL include both code and short_url (domain + "/" + code)

#### Scenario: Domain entry not found

- **GIVEN** a group_id whose domain entry is deleted or not configured
- **WHEN** POST /api/v1/shorten/gen is called
- **THEN** the system SHALL return an error indicating domain is not available
- **AND** the system SHALL NOT retry link creation

### Requirement: Disable short link

The system SHALL provide an endpoint to disable (deactivate) a short link.

#### Scenario: Disable active link

- **GIVEN** an authenticated request for an active link
- **WHEN** PUT /api/v1/shorten/disable is called with the code
- **THEN** the system SHALL set the link status to 2 (disabled)
- **AND** the system SHALL invalidate the cache entry
- **AND** the response SHALL confirm success

#### Scenario: Disable already disabled link

- **GIVEN** a link that is already disabled
- **WHEN** PUT /api/v1/shorten/disable is called
- **THEN** the response SHALL return an error indicating the link is already disabled
- **AND** the system SHALL NOT change any state

### Requirement: Unified response format

The system SHALL return all management API responses in a unified JSON format.

#### Scenario: Success response

- **GIVEN** any successful management API call
- **WHEN** the response is generated
- **THEN** the JSON body SHALL have fields: code (0 for success), message ("success"), data (result object)

#### Scenario: Error response

- **GIVEN** any failed management API call
- **WHEN** the response is generated
- **THEN** the JSON body SHALL have fields: code (non-zero error code), message (error description), data (null)

### Requirement: Tenant-constrained disable and endpoint validation

Disable SHALL accept only the required code parameter and SHALL update only links in groups currently granted to the authenticated tenant.

#### Scenario: Foreign tenant code

- **GIVEN** tenant A created an active link and tenant B is authenticated without that group grant
- **WHEN** tenant B attempts to disable that code
- **THEN** the response SHALL be 404 and the link SHALL remain active

#### Scenario: Missing disable code

- **GIVEN** an authenticated disable request without code
- **WHEN** endpoint validation runs
- **THEN** the response SHALL be 400 JSON with data:null, not 500

### Requirement: Single short-link creation path
`create` 与 `gen` SHALL 复用同一个创建用例；`gen` 只增加完整短 URL 输出。创建 SHALL 校验租户 Group 授权、Group 启用及 DomainEntry 已投产。
#### Scenario: Create and gen parity
- **GIVEN** 同一有效输入和授权
- **WHEN** 分别调用 create 与 gen
- **THEN** 两者 SHALL 使用相同创建规则；gen SHALL 返回 short_url
#### Scenario: Immutable target
- **GIVEN** 短链已创建
- **WHEN** 尝试修改 target_url
- **THEN** 系统 SHALL 拒绝修改
### Requirement: Terminal disable
短链停用 SHALL 为终态，且停用操作 SHALL 重新验证调用租户对所属 Group 的授权。
#### Scenario: Unauthorized disable
- **GIVEN** 调用租户无 Group 授权
- **WHEN** 请求停用某短码
- **THEN** 操作 SHALL 被拒绝，短链仍有效

### Requirement: Separate platform and tenant security boundaries
租户 `/api/v1/shorten/*` SHALL 保留 AK/SK 认证；平台 `/api/v1/admin/*` SHALL 仅向内部运维网络开放，不使用租户身份代替管理员会话。React Admin 的会话认证 SHALL 单独设计，浏览器 SHALL NOT 收到租户 SK。
#### Scenario: External platform administration request
- **GIVEN** 请求来自平台管理允许网络之外
- **WHEN** 访问 `/api/v1/admin/*`
- **THEN** Nginx SHALL 拒绝该请求，不因携带租户签名而放行
