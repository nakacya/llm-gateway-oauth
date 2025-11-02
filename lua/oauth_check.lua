-- oauth_check.lua
-- OAuth認証チェック

local cjson = require "cjson"

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

ngx.log(ngx.INFO, "OAuth authenticated user: ", user_email)
