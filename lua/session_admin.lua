-- session_admin.lua
-- 管理者用OAuth2セッション管理API
-- セッション一覧・削除（強制ログアウト）
-- Version: 2025/11/06 v2 - 削除フラグ方式対応

local redis = require "resty.redis"
local cjson = require "cjson"

-- スーパー管理者（最初の管理者、変更不可）
local SUPER_ADMINS = {
    [os.getenv("SUPER_ADMIN_EMAIL") or "nakacya@gmail.com"] = true
}

-- Redis接続
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)
    
    local redis_host = ngx.shared.jwt_secrets:get("redis_host") or "redis"
    local redis_port = tonumber(ngx.shared.jwt_secrets:get("redis_port")) or 6379
    
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        return nil, "Failed to connect to Redis: " .. err
    end
    
    return red
end

-- スーパー管理者チェック
local function is_super_admin(email)
    return SUPER_ADMINS[email] == true
end

-- 管理者チェック
local function is_admin(email)
    if is_super_admin(email) then
        return true
    end
    
    local admin_emails_env = os.getenv("ADMIN_EMAILS")
    if admin_emails_env then
        for admin_email in string.gmatch(admin_emails_env, "[^,]+") do
            admin_email = admin_email:match("^%s*(.-)%s*$")
            if email == admin_email then
                return true
            end
        end
    end
    
    return false
end

-- レスポンス送信
local function send_response(status, data)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(data))
    ngx.exit(status)
end

-- OAuth2セッション情報のパース
local function parse_session_data(session_data)
    -- OAuth2 Proxyのセッションデータは通常JSON形式
    local ok, data = pcall(cjson.decode, session_data)
    if ok then
        return data
    end
    
    -- パースできない場合は生データを返す
    return {raw = session_data}
end

-- 🆕 削除フラグを作成
local function create_deletion_flag(red, user_email)
    local flag_key = "active_user_deleted:" .. user_email
    local flag_ttl = 60  -- 60秒間有効
    
    -- フラグを作成（値はタイムスタンプ）
    local ok, err = red:setex(flag_key, flag_ttl, ngx.time())
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to create deletion flag for: ", user_email, " error: ", err)
        return false
    end
    
    ngx.log(ngx.INFO, "Created deletion flag for: ", user_email, " TTL: ", flag_ttl, "s")
    return true
end

-- OAuth2認証チェック
local email_header = ngx.var.http_x_forwarded_email
if not email_header or email_header == "" then
    send_response(401, {error = "Authentication required"})
end

-- 管理者チェック
if not is_admin(email_header) then
    send_response(403, {error = "Admin access only", user = email_header})
end

-- Redis接続
local red, err = connect_redis()
if not red then
    send_response(500, {error = "Redis connection failed", message = err})
end

-- リクエストメソッド処理
local method = ngx.req.get_method()
local uri = ngx.var.uri

-- GET /api/admin/sessions - 全セッション一覧
if method == "GET" and uri == "/api/admin/sessions" then
    -- OAuth2 Proxyのセッションキーを検索
    -- 実際の形式: _oauth2_proxy-{hash} (ハイフン)
    
    local session_patterns = {
        "_oauth2_proxy-*",      -- ハイフン形式（実際の形式）
        "_oauth2_proxy_*",      -- アンダースコア形式（念のため）
        "_oauth2_proxy:*",      -- コロン形式（念のため）
        "oauth2-*",
        "oauth2_*",
        "session:*"
    }
    
    local all_sessions = {}
    local total_count = 0
    
    for _, pattern in ipairs(session_patterns) do
        local keys, err = red:keys(pattern)
        
        if keys and type(keys) == "table" then
            for _, key in ipairs(keys) do
                -- セッションデータを取得
                local session_data, err = red:get(key)
                
                if session_data and session_data ~= ngx.null then
                    local ttl, err = red:ttl(key)
                    
                    local parsed_data = parse_session_data(session_data)
                    
                    table.insert(all_sessions, {
                        session_key = key,
                        email = parsed_data.email or parsed_data.user or "unknown",
                        created_at = parsed_data.created_at or parsed_data.iat,
                        expires_at = parsed_data.expires_at or parsed_data.exp,
                        ttl_seconds = ttl or -1,
                        data = parsed_data
                    })
                    
                    total_count = total_count + 1
                end
            end
        end
    end
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        sessions = all_sessions,
        total = total_count,
        patterns_searched = session_patterns
    })

-- DELETE /api/admin/sessions/{session_key} - セッション削除（強制ログアウト）
elseif method == "DELETE" and uri:match("^/api/admin/sessions/") then
    local session_key = uri:match("^/api/admin/sessions/(.+)")
    
    if not session_key then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Session key required"})
    end
    
    -- URLデコード
    session_key = ngx.unescape_uri(session_key)
    
    -- セッションを削除
    local result, err = red:del(session_key)
    
    if not result then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to delete session", message = err})
    end
    
    if result == 0 then
        red:set_keepalive(10000, 100)
        send_response(404, {error = "Session not found", session_key = session_key})
    end
    
    red:set_keepalive(10000, 100)
    
    ngx.log(ngx.INFO, "Session deleted: ", session_key, " by admin: ", email_header)
    
    send_response(200, {
        message = "Session deleted successfully",
        session_key = session_key,
        deleted_by = email_header
    })

-- POST /api/admin/sessions/revoke-user - 特定ユーザーの全セッションを削除
elseif method == "POST" and uri == "/api/admin/sessions/revoke-user" then
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Request body required"})
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Invalid JSON"})
    end
    
    local user_email = data.user_email
    if not user_email then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "user_email required"})
    end
    
    local session_patterns = {
        "_oauth2_proxy-*",      -- ハイフン形式（実際の形式）
        "_oauth2_proxy_*",      -- アンダースコア形式（念のため）
        "_oauth2_proxy:*",      -- コロン形式（念のため）
        "oauth2-*",
        "oauth2_*",
        "session:*"
    }
    
    local deleted_count = 0
    
    for _, pattern in ipairs(session_patterns) do
        local keys, err = red:keys(pattern)
        
        if keys and type(keys) == "table" then
            for _, key in ipairs(keys) do
                local session_data, err = red:get(key)
                
                if session_data and session_data ~= ngx.null then
                    local parsed_data = parse_session_data(session_data)
                    local session_email = parsed_data.email or parsed_data.user
                    
                    -- ユーザーのメールアドレスと一致する場合は削除
                    if session_email == user_email then
                        red:del(key)
                        deleted_count = deleted_count + 1
                        ngx.log(ngx.INFO, "Session deleted for user: ", user_email, " key: ", key)
                    end
                end
            end
        end
    end
    
    -- 🆕 active_userキーとメタデータを削除
    local active_user_key = "active_user:" .. user_email
    local metadata_key = "active_user_metadata:" .. user_email
    
    red:del(active_user_key)
    red:del(metadata_key)
    
    ngx.log(ngx.INFO, "Deleted active_user keys for: ", user_email)
    
    -- 🆕 削除フラグを作成（60秒間有効）
    create_deletion_flag(red, user_email)
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        message = "User sessions deleted successfully",
        user_email = user_email,
        deleted_count = deleted_count,
        deleted_by = email_header,
        deletion_flag_created = true,
        deletion_flag_ttl = 60
    })

-- GET /api/admin/sessions/stats - セッション統計
elseif method == "GET" and uri == "/api/admin/sessions/stats" then
    local session_patterns = {
        "_oauth2_proxy-*",      -- ハイフン形式（実際の形式）
        "_oauth2_proxy_*",      -- アンダースコア形式（念のため）
        "_oauth2_proxy:*",      -- コロン形式（念のため）
        "oauth2-*",
        "oauth2_*",
        "session:*"
    }
    
    local total_sessions = 0
    local user_sessions = {}
    
    for _, pattern in ipairs(session_patterns) do
        local keys, err = red:keys(pattern)
        
        if keys and type(keys) == "table" then
            for _, key in ipairs(keys) do
                local session_data, err = red:get(key)
                
                if session_data and session_data ~= ngx.null then
                    total_sessions = total_sessions + 1
                    
                    local parsed_data = parse_session_data(session_data)
                    local user = parsed_data.email or parsed_data.user or "unknown"
                    
                    if not user_sessions[user] then
                        user_sessions[user] = 0
                    end
                    user_sessions[user] = user_sessions[user] + 1
                end
            end
        end
    end
    
    -- ユニークユーザー数を計算
    local unique_users = 0
    for _, _ in pairs(user_sessions) do
        unique_users = unique_users + 1
    end
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        total_sessions = total_sessions,
        unique_users = unique_users,
        user_sessions = user_sessions
    })

else
    red:set_keepalive(10000, 100)
    send_response(405, {error = "Method not allowed"})
end
