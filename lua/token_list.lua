-- token_list.lua
-- ユーザーのトークン一覧取得

local cjson = require "cjson"
local redis = require "resty.redis"

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

-- Redis接続
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

-- ユーザーのトークンID一覧を取得
local token_ids, err = red:smembers("user:tokens:" .. user_email)
if not token_ids then
    red:set_keepalive(10000, 100)
    ngx.status = ngx.HTTP_OK
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        success = true,
        tokens = {},
        count = 0
    }))
    return
end

-- 各トークンの詳細情報を取得
local tokens = {}
for _, token_id in ipairs(token_ids) do
    local token_json, err = red:get("token:info:" .. token_id)
    if token_json and token_json ~= ngx.null then
        local token_data = cjson.decode(token_json)
        
        -- 有効期限チェック
        if token_data.expires_at > ngx.time() then
            -- トークン文字列は含めない（セキュリティのため）
            table.insert(tokens, {
                token_id = token_data.token_id,
                token_name = token_data.token_name,
                scopes = token_data.scopes,
                created_at = token_data.created_at,
                expires_at = token_data.expires_at,
                last_used = token_data.last_used,
                is_expired = false
            })
        else
            -- 期限切れトークンは削除
            red:del("token:info:" .. token_id)
            red:srem("user:tokens:" .. user_email, token_id)
        end
    end
end

red:set_keepalive(10000, 100)

-- レスポンス
ngx.status = ngx.HTTP_OK
ngx.header.content_type = "application/json"
ngx.say(cjson.encode({
    success = true,
    tokens = tokens,
    count = #tokens,
    user_email = user_email
}))
