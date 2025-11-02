-- key_generate_handler.lua
-- Virtual Key発行用ハンドラー
-- OAuth2 Proxyの /oauth2/auth エンドポイントを使ってユーザー情報を取得

local cjson = require "cjson"
local http = require "resty.http"

ngx.log(ngx.INFO, "========== key_generate_handler.lua START ==========")
ngx.log(ngx.INFO, "Request URI: ", ngx.var.request_uri)
ngx.log(ngx.INFO, "Method: ", ngx.req.get_method())

-- エラーレスポンス
local function send_error(status, message)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({error = message}))
    return ngx.exit(status)
end

-- 1. Cookieを確認
local cookie_header = ngx.var.http_cookie
if not cookie_header or not string.find(cookie_header, "_oauth2_proxy=") then
    ngx.log(ngx.ERR, "No OAuth2 cookie found")
    return send_error(401, "Authentication required. Please log in first.")
end

ngx.log(ngx.INFO, "OAuth2 cookie found: ", string.sub(cookie_header, 1, 50), "...")

-- 2. OAuth2 Proxyの /oauth2/auth に問い合わせてユーザー情報を取得
local httpc = http.new()
httpc:set_timeout(2000) -- 2秒タイムアウト

ngx.log(ngx.INFO, "Querying OAuth2 Proxy for user authentication...")

local res, err = httpc:request_uri("http://oauth2-proxy:4180/oauth2/auth", {
    method = "GET",
    headers = {
        ["Cookie"] = cookie_header,
        ["X-Forwarded-Proto"] = "http",
        ["X-Forwarded-Host"] = "litellm.nakacya.jp",
        ["X-Forwarded-Uri"] = "/key/generate"
    }
})

if not res then
    ngx.log(ngx.ERR, "Failed to query OAuth2 Proxy: ", err)
    return send_error(500, "Authentication service error: " .. (err or "unknown"))
end

ngx.log(ngx.INFO, "OAuth2 Proxy response status: ", res.status)

-- 3. レスポンスステータスの確認
if res.status ~= 202 and res.status ~= 200 then
    ngx.log(ngx.ERR, "OAuth2 authentication failed with status: ", res.status)
    ngx.log(ngx.INFO, "Response body: ", res.body or "empty")
    return send_error(401, "Session expired or invalid. Please log in again.")
end

-- 4. レスポンスヘッダーからユーザー情報を取得
-- OAuth2 Proxyは小文字のヘッダー名を使うことがある
local email = res.headers["X-Auth-Request-Email"] or 
              res.headers["x-auth-request-email"]
local user = res.headers["X-Auth-Request-User"] or 
             res.headers["x-auth-request-user"] or 
             email

if not email then
    ngx.log(ngx.ERR, "No email in OAuth2 Proxy response headers")
    
    -- デバッグ: すべてのヘッダーをログに出力
    for k, v in pairs(res.headers) do
        ngx.log(ngx.INFO, "Response header: ", k, " = ", v)
    end
    
    return send_error(401, "Invalid authentication response: no email found")
end

ngx.log(ngx.INFO, "✓ User authenticated via OAuth2 Proxy")
ngx.log(ngx.INFO, "  Email: ", email)
ngx.log(ngx.INFO, "  User: ", user)

-- 5. MASTER_KEYの取得と設定
local master_key = os.getenv("LITELLM_MASTER_KEY")
if not master_key or master_key == "" then
    ngx.log(ngx.ERR, "LITELLM_MASTER_KEY environment variable not set")
    return send_error(500, "Server configuration error: MASTER_KEY not configured")
end

ngx.log(ngx.INFO, "MASTER_KEY found: ", string.sub(master_key, 1, 10), "...")

-- 6. Authorizationヘッダーを設定
ngx.req.set_header("Authorization", "Bearer " .. master_key)
ngx.req.set_header("X-Authenticated-User", user)
ngx.req.set_header("X-Authenticated-Email", email)

ngx.log(ngx.INFO, "✓ MASTER_KEY set for user: ", email)
ngx.log(ngx.INFO, "========== key_generate_handler.lua END (SUCCESS) ==========")

-- 正常終了（proxy_pass に処理を渡す）
