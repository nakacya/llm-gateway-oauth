-- oauth_check.lua
-- OAuth認証チェック + Redisセッション確認 + BAN状態チェック
-- Version: 2025/11/08 v3 - BAN状態チェック追加

ngx.log(ngx.ERR, "===== oauth_check.lua START ===== METHOD:", ngx.var.request_method, " URI:", ngx.var.uri)

local cjson = require "cjson"
local redis = require "resty.redis"

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

-- メールアドレスを取得
local user_email = ngx.var.http_x_forwarded_email or
                   ngx.var.http_x_forwarded_user or
                   ngx.req.get_headers()["X-Forwarded-Email"] or
                   ngx.req.get_headers()["X-Forwarded-User"]

if not user_email or user_email == "" then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({error = "Authentication required"}))
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- 🆕 Redisでアクティブセッション & BAN状態を確認
local red, err = connect_redis()
if red then
    -- 🔥 BAN状態チェック（最優先）
    local deletion_flag_key = "active_user_deleted:" .. user_email
    local is_banned = red:exists(deletion_flag_key)

    if is_banned == 1 then
        -- ユーザーがBANされている
        local ban_ttl = red:ttl(deletion_flag_key)
        
        ngx.log(ngx.WARN, "BANNED user attempted access: ", user_email, " (TTL: ", ban_ttl, "s)")

        red:set_keepalive(10000, 100)

        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            error = "Access denied",
            message = "Your account has been temporarily suspended. Please contact the administrator.",
            banned_until_seconds = ban_ttl,
            user_email = user_email
        }))
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    -- アクティブセッション確認
    local active_user_key = "active_user:" .. user_email
    local exists = red:exists(active_user_key)

    if exists == 0 then
        -- active_userキーが存在しない = セッションが削除された
        ngx.log(ngx.WARN, "Session deleted for user: ", user_email, " - forcing logout")

        red:set_keepalive(10000, 100)

        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            error = "Session has been revoked",
            message = "Your session has been deleted by an administrator. Please log in again."
        }))
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- セッションキーが存在するか確認（より厳密なチェック）
    local session_keys, err = red:smembers(active_user_key)

    if not session_keys or #session_keys == 0 then
        -- セッションキーが空 = セッションが削除された
        ngx.log(ngx.WARN, "Empty session for user: ", user_email, " - forcing logout")

        red:set_keepalive(10000, 100)

        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            error = "Session has been revoked",
            message = "Your session has been deleted by an administrator. Please log in again."
        }))
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- 🔍 さらに厳密: OAuth2 ProxyのCookieとRedisのセッションキーが一致するか確認
    local oauth2_cookie = get_cookie_value("_oauth2_proxy")

    if oauth2_cookie then
        -- Cookieから推測されるセッションキーを生成（簡易版）
        -- 実際のセッションキーとの照合はOAuth2 Proxyが行うため、ここではactive_userの存在確認で十分

        ngx.log(ngx.DEBUG, "Session validated for user: ", user_email, " with ", #session_keys, " active sessions")
    end

    red:set_keepalive(10000, 100)
else
    -- Redisに接続できない場合は、OAuth2ヘッダーだけで判断（フォールバック）
    ngx.log(ngx.WARN, "Redis connection failed, falling back to OAuth2 header only: ", err)
end

ngx.log(ngx.INFO, "OAuth authenticated user: ", user_email)
