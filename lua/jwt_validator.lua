-- jwt_validator.lua
-- JWT検証モジュール

local jwt = require "resty.jwt"
local jwt_validators = require "resty.jwt-validators"
local redis = require "resty.redis"

local _M = {}

-- Redis接続ヘルパー
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

-- トークンが失効されているかチェック
local function is_token_revoked(jti)
    local red, err = connect_redis()
    if not red then
        return false  -- Redisエラー時は継続
    end
    
    local revoked, err = red:get("revoked:token:" .. jti)
    red:set_keepalive(10000, 100)
    
    if revoked == "1" then
        return true
    end
    
    return false
end

-- JWT検証メイン関数
function _M.validate(token)
    if not token or token == "" then
        return {
            valid = false,
            reason = "Token is missing"
        }
    end
    
    -- JWT秘密鍵を取得
    local jwt_secret = ngx.shared.jwt_secrets:get("secret")
    if not jwt_secret then
        ngx.log(ngx.ERR, "JWT secret not found in shared memory")
        return {
            valid = false,
            reason = "Server configuration error"
        }
    end
    
    -- JWTを検証
    local jwt_obj = jwt:verify(jwt_secret, token, {
        exp = jwt_validators.opt_is_not_expired(),
        nbf = jwt_validators.opt_is_not_before()
    })
    
    if not jwt_obj.verified then
        ngx.log(ngx.WARN, "JWT verification failed: ", jwt_obj.reason or "unknown")
        return {
            valid = false,
            reason = jwt_obj.reason or "Invalid token"
        }
    end
    
    local payload = jwt_obj.payload
    
    -- 必須フィールドのチェック
    if not payload.user_email then
        return {
            valid = false,
            reason = "Token missing user_email"
        }
    end
    
    -- トークンが失効されているかチェック
    if payload.jti and is_token_revoked(payload.jti) then
        return {
            valid = false,
            reason = "Token has been revoked"
        }
    end
    
    -- 検証成功
    return {
        valid = true,
        user_email = payload.user_email,
        user_id = payload.user_id,
        token_name = payload.token_name,
        jti = payload.jti,
        exp = payload.exp,
        iat = payload.iat
    }
end

return _M

