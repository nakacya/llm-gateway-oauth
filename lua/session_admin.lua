-- session_admin.lua
-- 管理者用OAuth2セッション管理API（拡張版）
-- Version: 2025/11/05 v3 - +を含むメールアドレス対応
--
-- 変更点:
--   - 🔧 url_decode() 関数を追加（+を正しく処理）
--   - 🔧 すべてのメールアドレスデコード処理を統一

local redis = require "resty.redis"
local cjson = require "cjson"

-- スーパー管理者（最初の管理者、変更不可）
local SUPER_ADMINS = {
    [os.getenv("SUPER_ADMIN_EMAIL") or "nakacya@gmail.com"] = true
}

-- 🆕 URLデコード関数（+を正しく処理）
local function url_decode(str)
    if not str then
        return nil
    end
    
    -- %XX形式のエンコードをデコード
    str = string.gsub(str, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    
    -- +をスペースに変換しない（メールアドレスの+を保護）
    -- 注: URLパラメータとして渡される場合、+は%2Bとしてエンコードされているはず
    
    return str
end

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

-- 🆕 active_userキーから特定のセッションキーを削除
local function remove_session_from_active_users(red, session_key)
    local removed_count = 0
    local cleaned_users = {}

    -- すべてのactive_user:*キーを検索
    local active_keys, err = red:keys("active_user:*")

    if active_keys and type(active_keys) == "table" then
        for _, active_key in ipairs(active_keys) do
            -- このactive_userキーにセッションキーが含まれているかチェック
            local is_member = red:sismember(active_key, session_key)

            if is_member == 1 then
                -- セッションキーを削除
                red:srem(active_key, session_key)
                removed_count = removed_count + 1

                -- メールアドレスを抽出
                local email = active_key:match("^active_user:(.+)$")
                table.insert(cleaned_users, email)

                ngx.log(ngx.INFO, "Removed session key from: ", active_key)

                -- セットが空になったかチェック
                local count = red:scard(active_key)
                if count == 0 then
                    -- 空になったらキーごと削除
                    red:del(active_key)
                    red:del("active_user_metadata:" .. email)
                    ngx.log(ngx.INFO, "Deleted empty active_user key: ", active_key)
                end
            end
        end
    end

    return removed_count, cleaned_users
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

-- ============================================
-- GET /api/admin/sessions/active-users
-- アクティブユーザー一覧を取得
-- ============================================
if method == "GET" and uri == "/api/admin/sessions/active-users" then
    -- active_user:* キーを検索
    local keys, err = red:keys("active_user:*")

    local active_users = {}

    if keys and type(keys) == "table" then
        for _, key in ipairs(keys) do
            -- メールアドレスを抽出
            local email = key:match("^active_user:(.+)$")

            if email then
                -- セッションキーを取得
                local session_keys, err = red:smembers(key)

                -- メタデータを取得
                local metadata_key = "active_user_metadata:" .. email
                local metadata_json, err = red:get(metadata_key)
                local metadata = {}

                if metadata_json and metadata_json ~= ngx.null then
                    local ok, parsed = pcall(cjson.decode, metadata_json)
                    if ok then
                        metadata = parsed
                    end
                end

                -- TTLを取得
                local ttl, err = red:ttl(key)

                table.insert(active_users, {
                    email = email,
                    session_count = #session_keys,
                    session_keys = session_keys,
                    created_at = metadata.created_at,
                    last_access = metadata.last_access,
                    expires_at = metadata.expires_at,
                    ttl_seconds = ttl or -1
                })
            end
        end
    end

    red:set_keepalive(10000, 100)

    send_response(200, {
        active_users = active_users,
        total = #active_users
    })

-- ============================================
-- 🆕 POST /api/admin/sessions/cleanup-orphaned
-- 孤立したセッションキーをクリーンアップ
-- ============================================
elseif method == "POST" and uri == "/api/admin/sessions/cleanup-orphaned" then
    local cleaned_count = 0
    local checked_count = 0
    local orphaned_sessions = {}

    -- すべてのactive_user:*キーを検索
    local active_keys, err = red:keys("active_user:*")

    if active_keys and type(active_keys) == "table" then
        for _, active_key in ipairs(active_keys) do
            local email = active_key:match("^active_user:(.+)$")
            local session_keys, err = red:smembers(active_key)

            if session_keys and type(session_keys) == "table" then
                for _, session_key in ipairs(session_keys) do
                    checked_count = checked_count + 1

                    -- セッションキーが実際にRedisに存在するかチェック
                    local exists = red:exists(session_key)

                    if exists == 0 then
                        -- 存在しない = 孤立セッション
                        red:srem(active_key, session_key)
                        cleaned_count = cleaned_count + 1

                        table.insert(orphaned_sessions, {
                            email = email,
                            session_key = session_key
                        })

                        ngx.log(ngx.INFO, "Removed orphaned session: ", session_key, " from: ", active_key)
                    end
                end

                -- セットが空になったかチェック
                local count = red:scard(active_key)
                if count == 0 then
                    red:del(active_key)
                    red:del("active_user_metadata:" .. email)
                    ngx.log(ngx.INFO, "Deleted empty active_user key: ", active_key)
                end
            end
        end
    end

    red:set_keepalive(10000, 100)

    send_response(200, {
        message = "Orphaned sessions cleaned up",
        checked_count = checked_count,
        cleaned_count = cleaned_count,
        orphaned_sessions = orphaned_sessions
    })

-- ============================================
-- 🔧 DELETE /api/admin/sessions/by-email/{email}
-- メールアドレス指定でセッションを削除（+対応版）
-- ============================================
elseif method == "DELETE" and uri:match("^/api/admin/sessions/by%-email/") then
    local user_email = uri:match("^/api/admin/sessions/by%-email/(.+)")

    if not user_email then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Email required"})
    end

    -- 🔧 修正: 独自のURLデコード関数を使用
    user_email = url_decode(user_email)
    
    -- デバッグログ
    ngx.log(ngx.INFO, "Deleting sessions for user (decoded): ", user_email)

    -- アクティブユーザーキーからセッションキーを取得
    local active_user_key = "active_user:" .. user_email
    local session_keys, err = red:smembers(active_user_key)

    if not session_keys or #session_keys == 0 then
        red:set_keepalive(10000, 100)
        send_response(404, {
            error = "No active sessions found for user",
            email = user_email,
            searched_key = active_user_key
        })
    end

    -- 全セッションキーを削除
    local deleted_count = 0
    for _, session_key in ipairs(session_keys) do
        local result, err = red:del(session_key)
        if result and result > 0 then
            deleted_count = deleted_count + 1
            ngx.log(ngx.INFO, "Session deleted: ", session_key)
        end
    end

    -- アクティブユーザーキーも削除
    red:del(active_user_key)
    red:del("active_user_metadata:" .. user_email)

    red:set_keepalive(10000, 100)

    ngx.log(ngx.INFO, "All sessions deleted for user: ", user_email, " by admin: ", email_header)

    send_response(200, {
        message = "User sessions deleted successfully",
        user_email = user_email,
        deleted_count = deleted_count,
        deleted_by = email_header
    })

-- ============================================
-- GET /api/admin/sessions - 全セッション一覧
-- ============================================
elseif method == "GET" and uri == "/api/admin/sessions" then
    -- OAuth2 Proxyのセッションキーを検索
    local session_patterns = {
        "_oauth2_proxy-*",
        "_oauth2_proxy_*",
        "_oauth2_proxy:*",
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

-- ============================================
-- 🔧 DELETE /api/admin/sessions/{session_key}
-- セッション削除（強制ログアウト） + active_user連動削除
-- ============================================
elseif method == "DELETE" and uri:match("^/api/admin/sessions/") then
    local session_key = uri:match("^/api/admin/sessions/(.+)")

    if not session_key then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Session key required"})
    end

    -- 🔧 修正: 独自のURLデコード関数を使用
    session_key = url_decode(session_key)

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

    -- 🆕 active_userキーからも削除
    local removed_count, cleaned_users = remove_session_from_active_users(red, session_key)

    red:set_keepalive(10000, 100)

    ngx.log(ngx.INFO, "Session deleted: ", session_key, " by admin: ", email_header,
            " (removed from ", removed_count, " active_user keys)")

    send_response(200, {
        message = "Session deleted successfully",
        session_key = session_key,
        deleted_by = email_header,
        removed_from_active_users = removed_count,
        cleaned_users = cleaned_users
    })

-- ============================================
-- POST /api/admin/sessions/revoke-user
-- 特定ユーザーの全セッションを削除（後方互換性のため維持）
-- ============================================
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

    -- 新しい方式：アクティブユーザーキーから削除
    local active_user_key = "active_user:" .. user_email
    local session_keys, err = red:smembers(active_user_key)

    local deleted_count = 0

    if session_keys and #session_keys > 0 then
        for _, session_key in ipairs(session_keys) do
            local result, err = red:del(session_key)
            if result and result > 0 then
                deleted_count = deleted_count + 1
                ngx.log(ngx.INFO, "Session deleted for user: ", user_email, " key: ", session_key)
            end
        end

        -- アクティブユーザーキーも削除
        red:del(active_user_key)
        red:del("active_user_metadata:" .. user_email)
    else
        -- 旧方式：全セッションをスキャン（後方互換性）
        local session_patterns = {
            "_oauth2_proxy-*",
            "_oauth2_proxy_*",
            "_oauth2_proxy:*",
            "oauth2-*",
            "oauth2_*",
            "session:*"
        }

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
    end

    red:set_keepalive(10000, 100)

    send_response(200, {
        message = "User sessions deleted successfully",
        user_email = user_email,
        deleted_count = deleted_count,
        deleted_by = email_header
    })

-- ============================================
-- GET /api/admin/sessions/stats - セッション統計
-- ============================================
elseif method == "GET" and uri == "/api/admin/sessions/stats" then
    local session_patterns = {
        "_oauth2_proxy-*",
        "_oauth2_proxy_*",
        "_oauth2_proxy:*",
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

    -- アクティブユーザー数を取得
    local active_user_keys, err = red:keys("active_user:*")
    local active_user_count = 0
    if active_user_keys and type(active_user_keys) == "table" then
        active_user_count = #active_user_keys
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
        active_tracked_users = active_user_count,
        user_sessions = user_sessions
    })

else
    red:set_keepalive(10000, 100)
    send_response(405, {error = "Method not allowed"})
end
