-- session_admin.lua
-- 管理者用OAuth2セッション管理API
-- セッション一覧・削除（強制ログアウト）
-- Version: 2025/11/08 v4.1 - Banned Users カウント修正（Redisから直接取得）

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

-- 🆕 削除フラグを作成（7日間有効）
local function create_deletion_flag(red, user_email)
    local flag_key = "active_user_deleted:" .. user_email
    local flag_ttl = 604800  -- 7日間（604800秒）有効

    -- フラグを作成（値はタイムスタンプ）
    local ok, err = red:setex(flag_key, flag_ttl, ngx.time())

    if not ok then
        ngx.log(ngx.ERR, "Failed to create deletion flag for: ", user_email, " error: ", err)
        return false
    end

    ngx.log(ngx.INFO, "Created deletion flag for: ", user_email, " TTL: ", flag_ttl, "s (7 days)")
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

-- 🆕 GET /api/admin/sessions/active-users - Active User一覧
if method == "GET" and uri == "/api/admin/sessions/active-users" then
    -- active_user:* キーを検索
    local active_user_keys, err = red:keys("active_user:*")

    if not active_user_keys or type(active_user_keys) ~= "table" then
        -- ★ Banned ユーザーのカウント（Redisから直接取得）
        local banned_keys, err = red:keys("active_user_deleted:*")
        local banned_count = 0
        if banned_keys and type(banned_keys) == "table" then
            banned_count = #banned_keys
        end
        
        red:set_keepalive(10000, 100)
        send_response(200, {
            active_users = {},
            total = 0,
            banned_count = banned_count
        })
    end

    local active_users = {}
    local current_time = ngx.time()

    for _, key in ipairs(active_user_keys) do
        -- メールアドレスを抽出
        local email = key:match("^active_user:(.+)$")

        if email then
            -- メタデータを取得
            local metadata_key = "active_user_metadata:" .. email
            local metadata_json = red:get(metadata_key)

            local metadata = {}
            if metadata_json and metadata_json ~= ngx.null then
                local ok, parsed = pcall(cjson.decode, metadata_json)
                if ok then
                    metadata = parsed
                end
            end

            -- セッション数を取得
            local session_count = red:scard(key)

            -- TTLを取得
            local ttl = red:ttl(key)

            -- 削除フラグの確認
            local deletion_flag_key = "active_user_deleted:" .. email
            local is_banned = red:exists(deletion_flag_key) == 1
            local ban_ttl = 0
            if is_banned then
                ban_ttl = red:ttl(deletion_flag_key)
            end

            table.insert(active_users, {
                email = email,
                session_count = tonumber(session_count) or 0,
                created_at = metadata.created_at or 0,
                last_access = metadata.last_access or 0,
                expires_at = metadata.expires_at or 0,
                ttl_seconds = tonumber(ttl) or -1,
                is_banned = is_banned,
                ban_remaining_seconds = tonumber(ban_ttl) or 0
            })
        end
    end

    -- 最終アクセス時刻でソート（新しい順）
    table.sort(active_users, function(a, b)
        return (a.last_access or 0) > (b.last_access or 0)
    end)

    -- ★ Banned ユーザーのカウント（修正版：Redisから直接取得）
    local banned_keys, err = red:keys("active_user_deleted:*")
    local banned_count = 0
    if banned_keys and type(banned_keys) == "table" then
        banned_count = #banned_keys
    end

    red:set_keepalive(10000, 100)

    send_response(200, {
        active_users = active_users,
        total = #active_users,
        banned_count = banned_count,  -- ★ 修正：Redisから直接カウント
        current_time = current_time
    })

-- GET /api/admin/sessions - 全セッション一覧
elseif method == "GET" and uri == "/api/admin/sessions" then
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

-- POST /api/admin/sessions/revoke-user - 特定ユーザーの全セッションを削除（即時BAN）
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

    -- active_userキーとメタデータを削除
    local active_user_key = "active_user:" .. user_email
    local metadata_key = "active_user_metadata:" .. user_email

    red:del(active_user_key)
    red:del(metadata_key)

    ngx.log(ngx.INFO, "Deleted active_user keys for: ", user_email)

    -- 🆕 削除フラグを作成（7日間有効）
    create_deletion_flag(red, user_email)

    red:set_keepalive(10000, 100)

    send_response(200, {
        message = "User sessions deleted successfully (BANNED for 7 days)",
        user_email = user_email,
        deleted_count = deleted_count,
        deleted_by = email_header,
        deletion_flag_created = true,
        deletion_flag_ttl = 604800  -- 7日間
    })

-- 🆕 DELETE /api/admin/sessions/unban/{email} - BAN解除（誤BAN対応）
elseif method == "DELETE" and uri:match("^/api/admin/sessions/unban/") then
    local user_email = uri:match("^/api/admin/sessions/unban/(.+)")

    if not user_email then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "User email required"})
    end

    -- URLデコード
    user_email = ngx.unescape_uri(user_email)

    -- 削除フラグを削除
    local deletion_flag_key = "active_user_deleted:" .. user_email
    local result = red:del(deletion_flag_key)

    if result == 0 then
        red:set_keepalive(10000, 100)
        send_response(404, {
            error = "Ban flag not found",
            user_email = user_email,
            message = "User is not currently banned"
        })
    end

    red:set_keepalive(10000, 100)

    ngx.log(ngx.INFO, "Ban flag removed for: ", user_email, " by admin: ", email_header)

    send_response(200, {
        message = "Ban removed successfully",
        user_email = user_email,
        unbanned_by = email_header
    })

-- 🆕 POST /api/admin/sessions/cleanup-expired - 期限切れactive_userの削除
elseif method == "POST" and uri == "/api/admin/sessions/cleanup-expired" then
    -- active_user:* キーを検索
    local active_user_keys, err = red:keys("active_user:*")

    if not active_user_keys or type(active_user_keys) ~= "table" then
        red:set_keepalive(10000, 100)
        send_response(200, {
            message = "No active users found",
            cleaned_count = 0
        })
    end

    local cleaned_users = {}
    local cleaned_count = 0
    local current_time = ngx.time()

    for _, key in ipairs(active_user_keys) do
        -- TTLを確認
        local ttl = red:ttl(key)

        -- TTLが-2（存在しない）または-1（期限なし）の場合はスキップ
        -- TTLが0以下（期限切れ）の場合のみ削除
        if ttl and ttl == -2 then
            -- キーが既に存在しない
            local email = key:match("^active_user:(.+)$")
            if email then
                table.insert(cleaned_users, email)
                cleaned_count = cleaned_count + 1
            end
        end
    end

    -- メタデータの孤立キーもクリーンアップ
    local metadata_keys, err = red:keys("active_user_metadata:*")

    if metadata_keys and type(metadata_keys) == "table" then
        for _, metadata_key in ipairs(metadata_keys) do
            local email = metadata_key:match("^active_user_metadata:(.+)$")
            if email then
                local active_user_key = "active_user:" .. email
                local exists = red:exists(active_user_key)

                -- active_userキーが存在しない場合はメタデータを削除
                if exists == 0 then
                    red:del(metadata_key)
                    ngx.log(ngx.INFO, "Cleaned orphaned metadata for: ", email)
                end
            end
        end
    end

    red:set_keepalive(10000, 100)

    ngx.log(ngx.INFO, "Cleanup expired active_users: ", cleaned_count, " cleaned by admin: ", email_header)

    send_response(200, {
        message = "Cleanup completed",
        cleaned_count = cleaned_count,
        cleaned_users = cleaned_users,
        cleaned_by = email_header
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
