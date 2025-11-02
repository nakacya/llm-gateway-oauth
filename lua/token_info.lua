-- token_info.lua
-- トークン情報取得エンドポイント

local cjson = require "cjson"
local jwt_validator = require "custom.jwt_validator"

-- OAuth認証チェック
local user_email = ngx.var.http_x_forwarded_email or
                   ngx.var.http_x_forwarded_user or
                   ngx.req.get_headers()["X-Forwarded-Email"] or
                   ngx.req.get_headers()["X-Forwarded-User"]

if not user_email or user_email == "" then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "Authentication required"
    }))
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- クエリパラメータからトークンIDを取得
local args = ngx.req.get_uri_args()
local token_id = args.token_id

if not token_id then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "token_id parameter is required"
    }))
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
end

-- Redisから情報取得
local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(1000)

local redis_host = ngx.shared.jwt_secrets:get("redis_host") or "redis"
local redis_port = tonumber(ngx.shared.jwt_secrets:get("redis_port")) or 6379

local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "Database connection failed"
    }))
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local token_json, err = red:get("token:info:" .. token_id)
red:set_keepalive(10000, 100)

if not token_json or token_json == ngx.null then
    ngx.status = ngx.HTTP_NOT_FOUND
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "Token not found or expired"
    }))
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local token_data = cjson.decode(token_json)

-- 権限チェック（自分のトークンのみ）
if token_data.user_email ~= user_email then
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "Access denied"
    }))
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

-- レスポンス
ngx.status = ngx.HTTP_OK
ngx.header.content_type = "application/json"
ngx.say(cjson.encode({
    success = true,
    token_info = token_data
}))
