-- active_user_tracker.lua
-- OAuth2認証後にアクティブユーザー情報をRedisに記録
-- Version: 2025/11/06 v9 - 削除フラグ方式対応
--
-- 変更点:
--   - セッション削除後の再ログイン防止機能追加
--   - active_user作成前に削除フラグをチェック
--   - 削除フラグが存在する場合は401エラーを返す

local redis = require "resty.redis"
local cjson = require "cjson"
local base64 = require "ngx.base64"

-- Redis接続
local function connect_redis()
    local red = redis:new()
    red:set_timeout(1000)

    local redis_host = ngx.shared.jwt_secrets:get("redis_host") or "redis"
    local redis_port = tonumber(ngx.shared.jwt_secrets:get("redis_port")) or 6379

    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return nil, err
    end

    return red
end

-- Cookieから特定の値を取得
local function get_cookie_value(cookie_name)
    local cookie_header = ngx.var.http_cookie

    if not cookie_header then
        return nil
    end

    local pattern = cookie_name .. "=([^;]+)"
    local cookie_value = string.match(cookie_header, pattern)

    return cookie_value
end

-- CookieからRedisキーを直接抽出
local function extract_session_key_from_cookie(cookie_value)
    -- Cookie形式: base64(v2.base64(session_key).signature)|timestamp|hmac

    -- Step 1: 最初の"|"より前の部分を抽出
    local session_token = cookie_value:match("^([^|]+)")

    if not session_token then
        ngx.log(ngx.ERR, "Failed to extract session token from cookie")
        return nil
    end

    ngx.log(ngx.DEBUG, "Session token: ", session_token)

    -- Step 2: Base64デコード（1回目）
    local decoded1 = base64.decode_base64url(session_token)
    if not decoded1 then
        ngx.log(ngx.ERR, "Failed to decode session token (1st)")
        return nil
    end

    ngx.log(ngx.DEBUG, "Decoded (1st): ", decoded1)

    -- Step 3: "v2."プレフィックスを確認
    if not decoded1:match("^v2%.") then
        ngx.log(ngx.WARN, "Session token is not v2 format: ", decoded1)
        -- v1形式の場合は、そのままdecoded1を使用
    end

    -- Step 4: "."で分割して2番目の部分を取得
    -- 形式: v2.base64(session_key).signature
    local parts = {}
    for part in decoded1:gmatch("[^.]+") do
        table.insert(parts, part)
    end

    if #parts < 2 then
        ngx.log(ngx.ERR, "Invalid session token format: ", decoded1)
        return nil
    end

    local session_key_encoded = parts[2]
    ngx.log(ngx.DEBUG, "Session key (encoded): ", session_key_encoded)

    -- Step 5: Base64デコード（2回目）
    local session_key = base64.decode_base64url(session_key_encoded)
    if not session_key then
        ngx.log(ngx.ERR, "Failed to decode session key (2nd)")
        return nil
    end

    ngx.log(ngx.INFO, "Extracted session key: ", session_key)

    return session_key
end

-- ============================================
-- メールアドレス取得（token_generator.luaと同じロジック）
-- ============================================
local headers = ngx.req.get_headers()
local email = headers["X-Forwarded-Email"] or
              headers["x-forwarded-email"] or
              ngx.var.http_x_forwarded_email or
              ngx.var.http_x_forwarded_user or
              ngx.var.arg___email

-- URLデコード
email = email and ngx.unescape_uri(email) or email

if not email or email == "" then
    ngx.log(ngx.DEBUG, "No email found in headers, skipping user tracking")
    ngx.status = 200
    ngx.say('{"status":"skipped","reason":"no_email"}')
    return
end

ngx.log(ngx.INFO, "Tracking active user: ", email)

-- ============================================
-- 🆕 削除フラグのチェック
-- ============================================
local red, err = connect_redis()
if not red then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    ngx.status = 500
    ngx.say('{"status":"error","reason":"redis_connection_failed"}')
    return
end

local deletion_flag_key = "active_user_deleted:" .. email
local flag_exists = red:exists(deletion_flag_key)

if flag_exists == 1 then
    -- 削除フラグが存在する場合は401エラーを返す
    ngx.log(ngx.WARN, "Deletion flag found for user: ", email, " - Blocking session creation")
    
    red:set_keepalive(10000, 100)
    
    ngx.status = 401
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        status = "blocked",
        reason = "session_deleted_recently",
        message = "Your session was deleted by an administrator. Please log in again.",
        email = email
    }))
    return ngx.exit(401)
end

ngx.log(ngx.DEBUG, "No deletion flag found for user: ", email, " - Proceeding with tracking")

-- ============================================
-- OAuth2 Proxyのセッションキーを取得
-- ============================================
local session_cookie = get_cookie_value("_oauth2_proxy")

if not session_cookie then
    ngx.log(ngx.WARN, "No OAuth2 session cookie found for user: ", email)
    red:set_keepalive(10000, 100)
    ngx.status = 200
    ngx.say('{"status":"skipped","reason":"no_session_cookie"}')
    return
end

-- CookieからRedisキーを直接抽出
local session_key = extract_session_key_from_cookie(session_cookie)

if not session_key then
    ngx.log(ngx.ERR, "Failed to extract session key from cookie")
    red:set_keepalive(10000, 100)
    ngx.status = 500
    ngx.say('{"status":"error","reason":"extraction_failed"}')
    return
end

local active_user_key = "active_user:" .. email
local metadata_key = "active_user_metadata:" .. email

ngx.log(ngx.INFO, "Session key: ", session_key)

-- ============================================
-- Active Userキーの管理（TTLは初回のみ設定）
-- ============================================
local ttl_seconds = 86400  -- 24時間
local current_time = ngx.time()

-- active_userキーが既に存在するかチェック
local exists = red:exists(active_user_key)

local created_at
if exists == 0 then
    -- 新規作成の場合
    ngx.log(ngx.INFO, "Creating new active_user key for: ", email)

    -- セッションキーをSetに追加
    red:sadd(active_user_key, session_key)

    -- TTLを設定（初回のみ）
    red:expire(active_user_key, ttl_seconds)

    created_at = current_time
else
    -- 既存のキーの場合
    ngx.log(ngx.INFO, "Updating existing active_user key for: ", email)

    -- セッションキーをSetに追加（重複は自動的に無視される）
    red:sadd(active_user_key, session_key)

    -- TTLはリセットしない！

    -- メタデータから作成時刻を取得
    local metadata_json = red:get(metadata_key)
    if metadata_json and metadata_json ~= ngx.null then
        local ok, metadata = pcall(cjson.decode, metadata_json)
        if ok and metadata.created_at then
            created_at = metadata.created_at
        else
            created_at = current_time
        end
    else
        created_at = current_time
    end
end

-- ============================================
-- メタデータの更新（最終アクセス時刻を記録）
-- ============================================
local expires_at = created_at + ttl_seconds

local metadata = {
    email = email,
    created_at = created_at,
    last_access = current_time,
    expires_at = expires_at,
    session_ttl = ttl_seconds,
    session_count = red:scard(active_user_key)
}

red:set(metadata_key, cjson.encode(metadata))

-- メタデータのTTLはactive_userキーと同じExpireに設定
local remaining_ttl = expires_at - current_time
if remaining_ttl > 0 then
    red:expire(metadata_key, remaining_ttl)
else
    red:del(metadata_key)
    red:del(active_user_key)
    ngx.log(ngx.WARN, "Active user key already expired for: ", email)
end

-- Redis接続をプールに返す
red:set_keepalive(10000, 100)

ngx.log(ngx.INFO, "Successfully tracked active user: ", email,
        " | created_at: ", created_at,
        " | expires_at: ", expires_at,
        " | last_access: ", current_time,
        " | remaining_ttl: ", remaining_ttl, "s")

-- 成功レスポンス
ngx.status = 200
ngx.header["Content-Type"] = "application/json"
ngx.say(cjson.encode({
    status = "success",
    email = email,
    session_key = session_key,
    created_at = created_at,
    expires_at = expires_at,
    last_access = current_time,
    remaining_ttl = remaining_ttl,
    session_count = metadata.session_count
}))
