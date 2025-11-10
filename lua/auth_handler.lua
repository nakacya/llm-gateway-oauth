-- auth_handler.lua
-- JWT認証ハンドラ（リクエストボディにuser追加版 + BAN状態チェック + Active User追跡）
-- 修正日: 2025-11-10 v2
-- 修正内容: 
--   - JWT認証成功後にBAN状態（active_user_deleted:*）をチェック
--   - active_user:{email}キーを作成（JWT token IDをSetに保存）
--   - session_countの計算を追加
--   - active_user_tracker.luaと同じ構造でメタデータを保存

local cjson = require "cjson"
local jwt_validator = require "custom.jwt_validator"
local redis = require "resty.redis"

ngx.log(ngx.INFO, "========== auth_handler.lua START ==========")

-- エラーレスポンス
local function send_error(status, message)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        error = {
            message = message,
            type = "authentication_error"
        }
    }))
    return ngx.exit(status)
end

-- Redis接続
local function connect_redis()
    local red = redis:new()
    red:set_timeouts(1000, 1000, 1000)
    
    local redis_host = ngx.shared.jwt_secrets:get("redis_host") or "redis"
    local redis_port = tonumber(ngx.shared.jwt_secrets:get("redis_port")) or 6379
    
    local ok, err = red:connect(redis_host, redis_port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return nil, err
    end
    
    return red
end

-- 1. JWT認証
local auth_header = ngx.var.http_authorization
if not auth_header or auth_header == "" then
    ngx.log(ngx.ERR, "No Authorization header")
    return send_error(401, "Authorization header required")
end

local token = auth_header:match("^Bearer%s+(.+)$")
if not token then
    ngx.log(ngx.ERR, "Invalid Authorization header format")
    return send_error(401, "Invalid Authorization header format")
end

local jwt_result = jwt_validator.validate(token)
if not jwt_result.valid then
    ngx.log(ngx.ERR, "JWT validation failed: ", jwt_result.reason or "unknown")
    return send_error(401, "Invalid or expired token: " .. (jwt_result.reason or "unknown"))
end

-- JWTからユーザー情報を取得
local user_email = jwt_result.user_email
local user_id = jwt_result.user_id or jwt_result.user_email
local token_name = jwt_result.token_name

ngx.log(ngx.INFO, "✓ JWT authentication successful: ", user_email)

-- 2. BAN状態チェック + Active User追跡（NEW）
local red, err = connect_redis()
if red then
    -- 2-1. BAN状態チェック
    local ban_key = "active_user_deleted:" .. user_email
    local ban_exists, redis_err = red:exists(ban_key)
    
    if redis_err then
        ngx.log(ngx.WARN, "Redis error checking BAN status: ", redis_err)
        -- Redis エラーの場合は処理を続行（可用性優先）
    elseif ban_exists == 1 then
        ngx.log(ngx.WARN, "⛔ User is BANNED: ", user_email)
        
        -- BAN残り時間を取得
        local ttl, ttl_err = red:ttl(ban_key)
        local ban_message = "User is temporarily banned"
        if ttl and ttl > 0 then
            local days = math.floor(ttl / 86400)
            local hours = math.floor((ttl % 86400) / 3600)
            ban_message = string.format("User is banned for %d days %d hours", days, hours)
        end
        
        -- Redis接続をプールに返却
        local ok, pool_err = red:set_keepalive(10000, 100)
        if not ok then
            ngx.log(ngx.WARN, "Failed to set keepalive: ", pool_err)
        end
        
        return send_error(401, ban_message)
    else
        ngx.log(ngx.INFO, "✓ User is not banned: ", user_email)
    end
    
    -- 2-2. Active User追跡（JWT認証でも追跡）
    local active_user_key = "active_user:" .. user_email
    local metadata_key = "active_user_metadata:" .. user_email
    local current_time = ngx.time()
    local ttl_seconds = 86400  -- 24時間
    
    -- JWTのトークンIDを取得（jwt_resultから）
    local token_id = jwt_result.token_id or jwt_result.jti or "jwt-session"
    
    -- active_userキーが既に存在するかチェック
    local exists = red:exists(active_user_key)
    
    local created_at
    if exists == 0 then
        -- 新規作成の場合
        ngx.log(ngx.INFO, "Creating new active_user key for: ", user_email, " (JWT)")
        
        -- トークンIDをSetに追加
        red:sadd(active_user_key, token_id)
        
        -- TTLを設定（初回のみ）
        red:expire(active_user_key, ttl_seconds)
        
        created_at = current_time
    else
        -- 既存のキーの場合
        ngx.log(ngx.INFO, "Updating existing active_user key for: ", user_email, " (JWT)")
        
        -- トークンIDをSetに追加（重複は自動的に無視される）
        red:sadd(active_user_key, token_id)
        
        -- 既存のメタデータから作成時刻を取得
        local metadata_json = red:get(metadata_key)
        if metadata_json and metadata_json ~= ngx.null then
            local ok, old_metadata = pcall(cjson.decode, metadata_json)
            if ok and old_metadata.created_at then
                created_at = old_metadata.created_at
            else
                created_at = current_time
            end
        else
            created_at = current_time
        end
    end
    
    -- メタデータの更新
    local expire_time = created_at + ttl_seconds
    local session_count_result = red:scard(active_user_key)
    local session_count = tonumber(session_count_result) or 1
    
    local metadata = cjson.encode({
        email = user_email,
        created_at = created_at,
        last_access = current_time,
        expire_at = expire_time,
        expires_at = expire_time,  -- token-session-manager互換性のため
        session_ttl = ttl_seconds,
        session_count = session_count,
        auth_method = "jwt",
        token_name = token_name or "unknown"
    })
    
    -- メタデータのTTLをactive_userキーと同じExpireに設定
    local remaining_ttl = expire_time - current_time
    if remaining_ttl > 0 then
        local set_ok, set_err = red:setex(metadata_key, remaining_ttl, metadata)
        if not set_ok then
            ngx.log(ngx.WARN, "Failed to save user metadata: ", set_err)
        else
            ngx.log(ngx.INFO, "✓ Active user metadata saved: ", user_email, " (JWT) | session_count: ", session_count)
        end
    else
        ngx.log(ngx.WARN, "Active user key already expired for: ", user_email)
        red:del(metadata_key)
        red:del(active_user_key)
    end
    
    -- active_usersセットに追加
    local sadd_ok, sadd_err = red:sadd("active_users", user_email)
    if not sadd_ok then
        ngx.log(ngx.WARN, "Failed to add to active_users set: ", sadd_err)
    else
        ngx.log(ngx.INFO, "✓ User added to active_users set: ", user_email)
    end
    
    -- Redis接続をプールに返却
    local ok, pool_err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.WARN, "Failed to set keepalive: ", pool_err)
    end
else
    ngx.log(ngx.WARN, "Could not connect to Redis for BAN check and tracking: ", err)
    -- Redis接続失敗の場合は処理を続行（可用性優先）
end

-- 3. 共有Virtual Keyに置き換え
local shared_key = os.getenv("LITELLM_SHARED_KEY")
if not shared_key or shared_key == "" then
    ngx.log(ngx.ERR, "LITELLM_SHARED_KEY not set")
    return send_error(500, "Server configuration error")
end

ngx.req.set_header("Authorization", "Bearer " .. shared_key)
ngx.log(ngx.INFO, "✓ Using shared Virtual Key")

-- 4. リクエストボディにuser情報を追加
ngx.log(ngx.INFO, ">>> Starting body processing...")

ngx.req.read_body()
local body = ngx.req.get_body_data()

-- メモリになければファイルから読む
if not body then
    local body_file = ngx.req.get_body_file()
    if body_file then
        ngx.log(ngx.INFO, "Reading body from temp file: ", body_file)
        local f = io.open(body_file, "r")
        if f then
            body = f:read("*all")
            f:close()
            ngx.log(ngx.INFO, "Read ", string.len(body), " bytes from file")
        end
    end
end

if body and body ~= "" then
    ngx.log(ngx.INFO, "Processing body: ", string.len(body), " bytes")

    local ok, json_data = pcall(cjson.decode, body)
    if ok and json_data then
        json_data.user = user_email
        json_data.metadata = json_data.metadata or {}
        json_data.metadata.user_email = user_email
        json_data.metadata.token_name = token_name or "unnamed"
        json_data.metadata.auth_method = "jwt"

        local new_body = cjson.encode(json_data)
        ngx.req.set_body_data(new_body)
        ngx.req.set_header("Content-Length", #new_body)

        ngx.log(ngx.INFO, "✓✓✓ Added user to request body: ", user_email)
    else
        ngx.log(ngx.ERR, "Failed to parse JSON")
    end
else
    ngx.log(ngx.WARN, "Body is empty or nil")
end

ngx.log(ngx.INFO, "========== auth_handler.lua END ==========")
