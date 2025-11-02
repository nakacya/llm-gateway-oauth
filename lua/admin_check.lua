-- admin_check.lua
-- 管理APIへのアクセスを二要素認証でチェック
-- 設定外部化版: 環境変数 + Redis で管理者を管理

local redis = require "resty.redis"
local cjson = require "cjson"

local master_key = os.getenv("LITELLM_MASTER_KEY")

-- ===== デバッグログ =====
ngx.log(ngx.INFO, "========== admin_check.lua START ==========")
ngx.log(ngx.INFO, "Request URI: ", ngx.var.request_uri)
ngx.log(ngx.INFO, "Remote addr: ", ngx.var.remote_addr)

-- Redis接続関数
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000) -- 1秒
    
    local redis_host = ngx.shared.jwt_secrets:get("redis_host") or "redis"
    local redis_port = tonumber(ngx.shared.jwt_secrets:get("redis_port")) or 6379
    
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return nil
    end
    
    return red
end

-- 管理者チェック関数
local function is_admin(email)
    ngx.log(ngx.INFO, "=== is_admin() called ===")
    ngx.log(ngx.INFO, "Email to check: ", email or "nil")
    
    if not email or email == "" then
        ngx.log(ngx.WARN, "Email is nil or empty")
        return false
    end
    
    -- 1. 環境変数から管理者リストをチェック
    local admin_emails_env = os.getenv("ADMIN_EMAILS")
    ngx.log(ngx.INFO, "ADMIN_EMAILS from env: ", admin_emails_env or "nil")
    
    if admin_emails_env then
        for admin_email in string.gmatch(admin_emails_env, "[^,]+") do
            admin_email = admin_email:match("^%s*(.-)%s*$") -- trim
            ngx.log(ngx.INFO, "Comparing '", email, "' with '", admin_email, "'")
            if email == admin_email then
                ngx.log(ngx.INFO, "✓ MATCH! Admin found in ADMIN_EMAILS: ", email)
                return true
            end
        end
        ngx.log(ngx.WARN, "No match in ADMIN_EMAILS")
    else
        ngx.log(ngx.WARN, "ADMIN_EMAILS environment variable not set")
    end
    
    -- 2. 環境変数から管理者ドメインをチェック
    local admin_domains_env = os.getenv("ADMIN_DOMAINS")
    ngx.log(ngx.INFO, "ADMIN_DOMAINS from env: ", admin_domains_env or "nil")
    
    if admin_domains_env then
        for domain in string.gmatch(admin_domains_env, "[^,]+") do
            domain = domain:match("^%s*(.-)%s*$") -- trim
            ngx.log(ngx.INFO, "Checking if '", email, "' ends with '@", domain, "'")
            if email:match("@" .. domain .. "$") then
                ngx.log(ngx.INFO, "✓ MATCH! Admin domain match: ", email, " -> ", domain)
                return true
            end
        end
        ngx.log(ngx.WARN, "No match in ADMIN_DOMAINS")
    end
    
    -- 3. Redisから管理者リストをチェック
    local red = connect_redis()
    if red then
        local is_member, err = red:sismember("admin:emails", email)
        if is_member == 1 then
            ngx.log(ngx.INFO, "✓ MATCH! Admin found in Redis: ", email)
            red:set_keepalive(10000, 100)
            return true
        end
        red:set_keepalive(10000, 100)
        ngx.log(ngx.WARN, "Not found in Redis")
    end
    
    ngx.log(ngx.WARN, "✗ NOT AN ADMIN: ", email)
    return false
end

-- 1. OAuth2セッションの確認
local user_header = ngx.var.http_x_forwarded_user
local email_header = ngx.var.http_x_forwarded_email

ngx.log(ngx.INFO, "X-Forwarded-User: ", user_header or "nil")
ngx.log(ngx.INFO, "X-Forwarded-Email: ", email_header or "nil")

if not user_header or user_header == "" then
    ngx.log(ngx.WARN, "No OAuth2 session found for admin access")
    ngx.status = 401
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"error": "Authentication required. Please log in via OAuth2."}')
    return ngx.exit(401)
end

-- 2. 管理者権限の確認
local is_admin_result = is_admin(email_header)
ngx.log(ngx.INFO, "is_admin() returned: ", tostring(is_admin_result))

if not is_admin_result then
    ngx.log(ngx.WARN, "Unauthorized admin access attempt by ", email_header)
    ngx.status = 403
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"error": "Insufficient privileges. Admin access only.", "user": "' .. email_header .. '"}')
    return ngx.exit(403)
end

-- 3. MASTER_KEY の確認と自動付与
local auth_header = ngx.var.http_authorization

if auth_header then
    local token = auth_header:match("^Bearer%s+(.+)$")
    
    -- MASTER_KEYと一致する場合はそのまま
    if token == master_key then
        ngx.log(ngx.INFO, "Valid MASTER_KEY provided by admin: ", email_header)
    else
        -- MASTER_KEYでない場合は上書き（UIからのトークンなど）
        ngx.log(ngx.INFO, "Overwriting non-MASTER_KEY token with MASTER_KEY for admin: ", email_header)
        if master_key and master_key ~= "" then
            ngx.req.set_header("Authorization", "Bearer " .. master_key)
        else
            ngx.log(ngx.ERR, "LITELLM_MASTER_KEY environment variable not set")
            ngx.status = 500
            ngx.header["Content-Type"] = "application/json"
            ngx.say('{"error": "Server configuration error: MASTER_KEY not configured"}')
            return ngx.exit(500)
        end
    end
else
    -- Authorizationヘッダーがない場合はMASTER_KEYを追加
    if master_key and master_key ~= "" then
        ngx.req.set_header("Authorization", "Bearer " .. master_key)
        ngx.log(ngx.INFO, "Auto-assigned MASTER_KEY for OAuth2 authenticated admin: ", email_header)
    else
        ngx.log(ngx.ERR, "LITELLM_MASTER_KEY environment variable not set")
        ngx.status = 500
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Server configuration error: MASTER_KEY not configured"}')
        return ngx.exit(500)
    end
end

-- 4. 監査ログ
ngx.log(ngx.INFO, "✓ Admin access granted: ", email_header, " from ", ngx.var.remote_addr)

-- 5. ユーザー情報をLiteLLMに渡す
ngx.req.set_header("X-Authenticated-User", user_header)
ngx.req.set_header("X-Authenticated-Email", email_header)
ngx.req.set_header("X-Admin-Action", "true")

ngx.log(ngx.INFO, "========== admin_check.lua END (SUCCESS) ==========")

-- 認証成功、次の処理へ
