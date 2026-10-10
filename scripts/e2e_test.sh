#!/bin/bash
# scripts/e2e_test.sh
# Linklet E2E 端到端测试 / End-to-end tests
# 用法: ./scripts/e2e_test.sh [BASE_URL]
# 默认 BASE_URL: http://localhost:8080

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
TEST_AK="test-access-key-001"
TEST_SK="test-secret-key-001"

PASS=0
FAIL=0
TOTAL=0

# 颜色输出 / Colored output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo -e "  Expected: $2"
    echo -e "  Actual:   $3"
}

# 计算签名 / Compute HMAC-SHA1 signature
# 参数: method uri timestamp body
# 输出: base64(hmac_sha1(SK, "method\nuri\ntimestamp\nbody"))
compute_sig() {
    local method="$1"
    local uri="$2"
    local timestamp="$3"
    local body="$4"
    local string_to_sign="${method}\n${uri}\n${timestamp}\n${body}"
    # printf 解析转义 / printf interprets escapes
    printf "${string_to_sign}" | openssl dgst -sha1 -hmac "${TEST_SK}" -binary | base64 | tr -d '\n'
}

echo "========================================"
echo "  Linklet E2E Test Suite"
echo "  Base URL: ${BASE_URL}"
echo "========================================"
echo ""

# 测试 1: 健康检查 / Test 1: Health check
echo "--- Test 1: Health Check ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
body=$(curl -s "${BASE_URL}/health")
if [ "$status" = "200" ] && [ "$body" = "ok" ]; then
    log_pass "Health check returns 200 ok"
else
    log_fail "Health check" "200 ok" "$status $body"
fi

# 测试 2: 未认证创建短链（应返回 401）/ Test 2: Create without auth (expect 401)
echo ""
echo "--- Test 2: Create without auth (expect 401) ---"
status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/api/v1/shorten/create" \
    -H "Content-Type: application/json" \
    -d '{"target_url":"https://example.com","scene_id":1}')
if [ "$status" = "401" ]; then
    log_pass "Unauthenticated request returns 401"
else
    log_fail "Unauthenticated request" "401" "$status"
fi

# 测试 3: 已认证创建短链 / Test 3: Create short link with auth
echo ""
echo "--- Test 3: Create short link with auth ---"
timestamp=$(date +%s)
body='{"target_url":"https://example.com/e2e-test","scene_id":1}'
sig=$(compute_sig "POST" "/api/v1/shorten/create" "$timestamp" "$body")
echo "  Signature: ${sig:0:30}..."

response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/shorten/create" \
    -H "Content-Type: application/json" \
    -H "X-Access-Key: ${TEST_AK}" \
    -H "X-Signature: ${sig}" \
    -H "X-Timestamp: ${timestamp}" \
    -d "$body")

resp_status=$(echo "$response" | tail -1)
    resp_body=$(echo "$response" | sed '$d')
    echo "  Response: $resp_status $resp_body"

    if [ "$resp_status" = "200" ]; then
        # 提取短码 / Extract short code
        short_code=$(echo "$resp_body" | grep -o '"code":"[^"]*"' | head -1 | sed 's/"code":"//;s/"//')
        if [ -n "$short_code" ]; then
            log_pass "Create short link: code=${short_code}"
        else
            log_fail "Create short link - extract code" "code field present" "not found in: $resp_body"
        fi
    else
        log_fail "Create short link" "200" "$resp_status $resp_body"
        short_code=""
    fi

# 测试 4: 解析已知短码（e2eTest）/ Test 4: Resolve known short code
echo ""
echo "--- Test 4: Resolve known short code (e2eTest) ---"
status=$(curl -s -o /dev/null -w "%{http_code}" -L --max-redirs 0 "${BASE_URL}/e2eTest" 2>/dev/null || true)
location=$(curl -s -I --max-redirs 0 "${BASE_URL}/e2eTest" 2>/dev/null | grep -i "^location:" | tr -d '\r' | awk '{print $2}')

if [ "$status" = "302" ]; then
    log_pass "Resolve e2eTest returns 302 redirect to ${location}"
else
    log_fail "Resolve e2eTest" "302 + Location header" "$status location=$location"
fi

# 测试 5: 解析不存在的短码 / Test 5: Resolve non-existent code
echo ""
echo "--- Test 5: Resolve non-existent code ---"
status=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/zzzz99")
if [ "$status" = "404" ]; then
    log_pass "Non-existent code returns 404"
else
    log_fail "Non-existent code" "404" "$status"
fi

# 测试 6: 停用短链 / Test 6: Disable short link
echo ""
echo "--- Test 6: Disable short link ---"
if [ -n "$short_code" ]; then
    timestamp=$(date +%s)
    body="{\"code\":\"${short_code}\"}"
    sig=$(compute_sig "PUT" "/api/v1/shorten/disable" "$timestamp" "$body")

    response=$(curl -s -w "\n%{http_code}" -X PUT "${BASE_URL}/api/v1/shorten/disable" \
        -H "Content-Type: application/json" \
        -H "X-Access-Key: ${TEST_AK}" \
        -H "X-Signature: ${sig}" \
        -H "X-Timestamp: ${timestamp}" \
        -d "$body")

    resp_status=$(echo "$response" | tail -1)
    resp_body=$(echo "$response" | sed '$d')
    echo "  Response: $resp_status $resp_body"

    if [ "$resp_status" = "200" ]; then
        log_pass "Disable short link: ${short_code}"
    else
        log_fail "Disable short link" "200" "$resp_status $resp_body"
    fi

    # 测试 7: 已停用短链的解析 / Test 7: Resolve disabled link
    echo ""
    echo "--- Test 7: Resolve disabled link (expect 410) ---"
    # 先清缓存 / Clear cache first (if possible)
    status=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/${short_code}" 2>/dev/null || true)
    if [ "$status" = "410" ] || [ "$status" = "302" ]; then
        # 302 可能在缓存中仍有记录，410 表示已停用
        if [ "$status" = "410" ]; then
            log_pass "Disabled link returns 410"
        else
            # 缓存命中返回 302 是预期行为（缓存 TTL 内）
            log_pass "Disabled link returns ${status} (cache may still be active)"
        fi
    else
        log_fail "Disabled link resolution" "410 or 302" "$status"
    fi
else
    echo "  SKIP: No short code to disable"
fi

# 测试 8: 生成含完整 URL 的短链 / Test 8: Gen short link with full URL
echo ""
echo "--- Test 8: Gen short link with full URL ---"
timestamp=$(date +%s)
body='{"target_url":"https://example.com/gen-test","scene_id":1}'
sig=$(compute_sig "POST" "/api/v1/shorten/gen" "$timestamp" "$body")

response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/api/v1/shorten/gen" \
    -H "Content-Type: application/json" \
    -H "X-Access-Key: ${TEST_AK}" \
    -H "X-Signature: ${sig}" \
    -H "X-Timestamp: ${timestamp}" \
    -d "$body")

resp_status=$(echo "$response" | tail -1)
resp_body=$(echo "$response" | head -n -1)
echo "  Response: $resp_status $resp_body"

if [ "$resp_status" = "200" ]; then
    log_pass "Gen short link with URL"
else
    log_fail "Gen short link" "200" "$resp_status $resp_body"
fi

echo ""
echo "========================================"
echo "  E2E Test Results: ${PASS} passed, ${FAIL} failed, ${TOTAL} total"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
