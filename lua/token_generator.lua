-- token_generator.lua
-- 期限付きトークン生成エンドポイント

local cjson = require "cjson"
local jwt = require "resty.jwt"
local redis = require "resty.redis"
local random = require "resty.random"
local str = require "resty.string"

-- UUIDv4生成
local function generate_uuid()
    local bytes = random.bytes(16)
    if not bytes then
        return str.to_hex(string.format("%d%d", ngx.time(), ngx.worker.pid()))
    end
    
    bytes = string.gsub(bytes, "(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)",
        function(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p)
            return string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                string.byte(a), string.byte(b), string.byte(c), string.byte(d),
                string.byte(e), string.byte(f),
                bit.bor(bit.band(string.byte(g), 0x0f), 0x40), string.byte(h),
                bit.bor(bit.band(string.byte(i), 0x3f), 0x80), string.byte(j),
                string.byte(k), string.byte(l), string.byte(m), string.byte(n), string.byte(o), string.byte(p))
        end)
    
    return bytes
end

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

-- トークン情報をRedisに保存
local function store_token_info(user_email, token_id, token_data, expiry)
    local red, err = connect_redis()
    if not red then
        return false, err
    end
    
    -- トークン情報をJSON化
    local token_json = cjson.encode(token_data)
    
    -- ユーザーごとのトークンリストに追加
    red:sadd("user:tokens:" .. user_email, token_id)
    
    -- トークン詳細情報を保存（有効期限付き）
    red:setex("token:info:" .. token_id, expiry, token_json)
    
    red:set_keepalive(10000, 100)
    return true
end

-- メイン処理
ngx.req.read_body()
local body = ngx.req.get_body_data()

-- OAuth認証チェック
local user_email = ngx.var.http_x_forwarded_email or
                   ngx.var.http_x_forwarded_user or
                   ngx.req.get_headers()["X-Forwarded-Email"] or
                   ngx.req.get_headers()["X-Forwarded-User"]

if not user_email or user_email == "" then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = "Authentication required. Please login via OAuth first."
    }))
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

-- リクエストボディのパース
local request_data = {}
if body and body ~= "" then
    local ok, data = pcall(cjson.decode, body)
    if ok then
        request_data = data
    end
end

-- トークン設定
local token_name = request_data.token_name or "API Token"
local expires_in = tonumber(request_data.expires_in) or 86400  -- デフォルト24時間
local scopes = request_data.scopes or {"api:read", "api:write"}

-- 有効期限の制限（最大90日）
if expires_in > 7776000 then
    expires_in = 7776000
end

-- JWT秘密鍵を取得
local jwt_secret = ngx.shared.jwt_secrets:get("secret")
if not jwt_secret then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({error = "Server configuration error"}))
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- トークンID生成
local token_id = generate_uuid()
local now = ngx.time()

-- JWTペイロード作成
local payload = {
    jti = token_id,
    user_email = user_email,
    user_id = user_email,
    token_name = token_name,
    scopes = scopes,
    iat = now,
    nbf = now,
    exp = now + expires_in,
    iss = "litellm.nakacya.jp",
    aud = "litellm-api"
}

-- JWT生成
local token = jwt:sign(jwt_secret, {
    header = {
        typ = "JWT",
        alg = "HS256"
    },
    payload = payload
})

-- トークン情報をRedisに保存
local token_info = {
    token_id = token_id,
    user_email = user_email,
    token_name = token_name,
    scopes = scopes,
    created_at = now,
    expires_at = now + expires_in,
    last_used = nil
}

local ok, err = store_token_info(user_email, token_id, token_info, expires_in)
if not ok then
    ngx.log(ngx.WARN, "Failed to store token info: ", err)
end

-- レスポンス
ngx.status = ngx.HTTP_OK
ngx.header.content_type = "application/json"
ngx.say(cjson.encode({
    success = true,
    token = token,
    token_type = "Bearer",
    token_id = token_id,
    token_name = token_name,
    expires_in = expires_in,
    expires_at = now + expires_in,
    created_at = now,
    scopes = scopes,
    user_email = user_email,
    usage_instructions = {
        curl = "curl -H 'Authorization: Bearer " .. token .. "' http://litellm.nakacya.jp/v1/...",
        roo_code = "Set this token as your API key in Roo Code settings"
    }
}))

ngx.log(ngx.INFO, "Token generated for user: ", user_email, " (", token_name, ")")
