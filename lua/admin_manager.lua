-- admin_manager.lua
-- 管理者の追加・削除・一覧を管理するAPI
-- OAuth2認証必須 + スーパー管理者のみアクセス可能

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

-- スーパー管理者チェック
if not is_super_admin(email_header) then
    send_response(403, {error = "Super admin only", user = email_header})
end

-- Redis接続
local red, err = connect_redis()
if not red then
    send_response(500, {error = "Redis connection failed", message = err})
end

-- リクエストメソッド処理
local method = ngx.req.get_method()

-- GET: 管理者一覧
if method == "GET" then
    local admins, err = red:smembers("admin:emails")
    
    if not admins then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to get admin list", message = err})
    end
    
    -- 環境変数からの管理者も追加
    local all_admins = {}
    for _, admin in ipairs(admins) do
        table.insert(all_admins, {
            email = admin,
            source = "redis",
            removable = true
        })
    end
    
    -- 環境変数の管理者
    local admin_emails_env = os.getenv("ADMIN_EMAILS")
    if admin_emails_env then
        for admin_email in string.gmatch(admin_emails_env, "[^,]+") do
            admin_email = admin_email:match("^%s*(.-)%s*$")
            table.insert(all_admins, {
                email = admin_email,
                source = "environment",
                removable = false
            })
        end
    end
    
    -- スーパー管理者
    for super_admin, _ in pairs(SUPER_ADMINS) do
        table.insert(all_admins, {
            email = super_admin,
            source = "super_admin",
            removable = false
        })
    end
    
    red:set_keepalive(10000, 100)
    send_response(200, {
        admins = all_admins,
        total = #all_admins
    })

-- POST: 管理者追加
elseif method == "POST" then
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
    
    local email = data.email
    if not email or email == "" then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Email required"})
    end
    
    -- メール形式チェック
    if not email:match("^[%w._%+-]+@[%w.-]+%.%w+$") then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Invalid email format"})
    end
    
    -- Redis に追加
    local result, err = red:sadd("admin:emails", email)
    
    if not result then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to add admin", message = err})
    end
    
    ngx.log(ngx.INFO, "Admin added: ", email, " by ", email_header)
    
    red:set_keepalive(10000, 100)
    send_response(201, {
        message = "Admin added successfully",
        email = email,
        added_by = email_header
    })

-- DELETE: 管理者削除
elseif method == "DELETE" then
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
    
    local email = data.email
    if not email or email == "" then
        red:set_keepalive(10000, 100)
        send_response(400, {error = "Email required"})
    end
    
    -- スーパー管理者は削除不可
    if SUPER_ADMINS[email] then
        red:set_keepalive(10000, 100)
        send_response(403, {error = "Cannot remove super admin"})
    end
    
    -- Redis から削除
    local result, err = red:srem("admin:emails", email)
    
    if not result then
        red:set_keepalive(10000, 100)
        send_response(500, {error = "Failed to remove admin", message = err})
    end
    
    if result == 0 then
        red:set_keepalive(10000, 100)
        send_response(404, {error = "Admin not found", email = email})
    end
    
    ngx.log(ngx.INFO, "Admin removed: ", email, " by ", email_header)
    
    red:set_keepalive(10000, 100)
    send_response(200, {
        message = "Admin removed successfully",
        email = email,
        removed_by = email_header
    })

else
    red:set_keepalive(10000, 100)
    send_response(405, {error = "Method not allowed", allowed = "GET, POST, DELETE"})
end
