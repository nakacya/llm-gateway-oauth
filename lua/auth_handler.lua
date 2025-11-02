-- auth_handler.lua
-- JWT認証ハンドラ（リクエストボディにuser追加版）

local cjson = require "cjson"
local jwt_validator = require "custom.jwt_validator"

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

-- 2. 共有Virtual Keyに置き換え
local shared_key = os.getenv("LITELLM_SHARED_KEY")
if not shared_key or shared_key == "" then
    ngx.log(ngx.ERR, "LITELLM_SHARED_KEY not set")
    return send_error(500, "Server configuration error")
end

ngx.req.set_header("Authorization", "Bearer " .. shared_key)
ngx.log(ngx.INFO, "✓ Using shared Virtual Key")

-- 3. リクエストボディにuser情報を追加
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
