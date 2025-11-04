-- token_admin.lua
-- 管理者用トークン管理API
-- 全ユーザーのトークン一覧・削除・詳細表示

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

-- 管理者チェック（環境変数からも確認）
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

-- GET /api/admin/tokens - 全トークン一覧
if method == "GET" and uri == "/api/admin/tokens" then
    -- Redisから全トークンユーザーを取得
    local keys, err = red:keys("user:tokens:*")
    
    if not keys then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to get token list", message = err})
    end
    
    local all_tokens = {}
    local total_count = 0
    local active_count = 0
    local expired_count = 0
    
    for _, key in ipairs(keys) do
        local user_email = key:match("user:tokens:(.+)")
        
        if user_email then
            local token_ids, err = red:smembers(key)
            
            if token_ids then
                for _, token_id in ipairs(token_ids) do
                    local token_json, err = red:get("token:info:" .. token_id)
                    
                    if token_json and token_json ~= ngx.null then
                        local ok, token_data = pcall(cjson.decode, token_json)
                        
                        if ok then
                            local is_expired = token_data.expires_at <= ngx.time()
                            local is_revoked = false
                            
                            -- 失効チェック
                            local revoked, err = red:get("revoked:token:" .. token_id)
                            if revoked == "1" then
                                is_revoked = true
                            end
                            
                            table.insert(all_tokens, {
                                token_id = token_data.token_id,
                                token_name = token_data.token_name,
                                user_email = token_data.user_email,
                                created_at = token_data.created_at,
                                expires_at = token_data.expires_at,
                                last_used = token_data.last_used,
                                is_expired = is_expired,
                                is_revoked = is_revoked,
                                status = is_revoked and "revoked" or (is_expired and "expired" or "active")
                            })
                            
                            total_count = total_count + 1
                            
                            if is_expired then
                                expired_count = expired_count + 1
                            elseif not is_revoked then
                                active_count = active_count + 1
                            end
                        end
                    end
                end
            end
        end
    end
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        tokens = all_tokens,
        summary = {
            total = total_count,
            active = active_count,
            expired = expired_count,
            revoked = total_count - active_count - expired_count
        }
    })

-- GET /api/admin/tokens/{user_email} - 特定ユーザーのトークン一覧
elseif method == "GET" and uri:match("^/api/admin/tokens/") then
    local user_email = uri:match("^/api/admin/tokens/(.+)")
    
    if not user_email then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "User email required"})
    end
    
    -- URLデコード
    user_email = ngx.unescape_uri(user_email)
    
    local token_ids, err = red:smembers("user:tokens:" .. user_email)
    
    if not token_ids then
        red:set_keepalive(10000, 100)
        send_response(200, {
            user_email = user_email,
            tokens = {},
            count = 0
        })
    end
    
    local tokens = {}
    
    for _, token_id in ipairs(token_ids) do
        local token_json, err = red:get("token:info:" .. token_id)
        
        if token_json and token_json ~= ngx.null then
            local ok, token_data = pcall(cjson.decode, token_json)
            
            if ok then
                local is_expired = token_data.expires_at <= ngx.time()
                local is_revoked = false
                
                local revoked, err = red:get("revoked:token:" .. token_id)
                if revoked == "1" then
                    is_revoked = true
                end
                
                table.insert(tokens, {
                    token_id = token_data.token_id,
                    token_name = token_data.token_name,
                    created_at = token_data.created_at,
                    expires_at = token_data.expires_at,
                    last_used = token_data.last_used,
                    is_expired = is_expired,
                    is_revoked = is_revoked,
                    status = is_revoked and "revoked" or (is_expired and "expired" or "active")
                })
            end
        end
    end
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        user_email = user_email,
        tokens = tokens,
        count = #tokens
    })

-- DELETE /api/admin/tokens/{token_id} - トークン削除（失効）
elseif method == "DELETE" and uri:match("^/api/admin/tokens/") then
    local token_id = uri:match("^/api/admin/tokens/(.+)")
    
    if not token_id then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Token ID required"})
    end
    
    -- URLデコード
    token_id = ngx.unescape_uri(token_id)
    
    -- トークン情報を取得
    local token_json, err = red:get("token:info:" .. token_id)
    
    if not token_json or token_json == ngx.null then
        red:set_keepalive(10000, 100)
        send_response(404, {error = "Token not found", token_id = token_id})
    end
    
    local ok, token_data = pcall(cjson.decode, token_json)
    if not ok then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to parse token data"})
    end
    
    -- 失効処理
    local ttl = token_data.expires_at - ngx.time()
    if ttl > 0 then
        red:setex("revoked:token:" .. token_id, ttl, "1")
    end
    
    -- トークン情報を削除
    red:del("token:info:" .. token_id)
    
    -- ユーザーのトークンリストから削除
    red:srem("user:tokens:" .. token_data.user_email, token_id)
    
    red:set_keepalive(10000, 100)
    
    ngx.log(ngx.INFO, "Token revoked: ", token_id, " by admin: ", email_header)
    
    send_response(200, {
        message = "Token revoked successfully",
        token_id = token_id,
        user_email = token_data.user_email,
        revoked_by = email_header
    })

-- POST /api/admin/tokens/revoke-user - 特定ユーザーの全トークンを失効
elseif method == "POST" and uri == "/api/admin/tokens/revoke-user" then
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
    
    -- ユーザーの全トークンを取得
    local token_ids, err = red:smembers("user:tokens:" .. user_email)
    
    if not token_ids then
        red:set_keepalive(10000, 100)
        send_response(404, {error = "User not found or no tokens", user_email = user_email})
    end
    
    local revoked_count = 0
    
    for _, token_id in ipairs(token_ids) do
        local token_json, err = red:get("token:info:" .. token_id)
        
        if token_json and token_json ~= ngx.null then
            local ok, token_data = pcall(cjson.decode, token_json)
            
            if ok then
                local ttl = token_data.expires_at - ngx.time()
                if ttl > 0 then
                    red:setex("revoked:token:" .. token_id, ttl, "1")
                end
                
                red:del("token:info:" .. token_id)
                revoked_count = revoked_count + 1
            end
        end
    end
    
    -- ユーザーのトークンリストを削除
    red:del("user:tokens:" .. user_email)
    
    red:set_keepalive(10000, 100)
    
    ngx.log(ngx.INFO, "All tokens revoked for user: ", user_email, " by admin: ", email_header)
    
    send_response(200, {
        message = "All tokens revoked successfully",
        user_email = user_email,
        revoked_count = revoked_count,
        revoked_by = email_header
    })

else
    red:set_keepalive(10000, 100)
    send_response(405, {error = "Method not allowed"})
end
