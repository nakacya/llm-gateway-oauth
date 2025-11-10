-- redis_cleanup.lua
-- Redisクリーンアップ機能（削除明細記録版）
-- 孤立データの削除とログ管理（監査証跡対応）
-- Version: 2025/11/10 v2.1 - 削除明細を追加

local redis = require "resty.redis"
local cjson = require "cjson"

-- スーパー管理者（最初の管理者、変更不可）
local SUPER_ADMINS = {
    [os.getenv("SUPER_ADMIN_EMAIL") or "nakacya@gmail.com"] = true
}

-- 環境変数から設定を取得
local CLEANUP_LOG_RETENTION_DAYS = tonumber(os.getenv("CLEANUP_LOG_RETENTION_DAYS")) or 30
local LOG_RETENTION_SECONDS = CLEANUP_LOG_RETENTION_DAYS * 86400

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

-- 管理者チェック
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

-- メモリサイズの推定（概算）
local function estimate_memory_size(key_count)
    local bytes = key_count * 500
    if bytes < 1024 then
        return string.format("%dB", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1fKB", bytes / 1024)
    else
        return string.format("%.1fMB", bytes / (1024 * 1024))
    end
end

-- 孤立したJWT Token ID（user:tokens内のゴミ）を検索
local function find_orphaned_jwt_token_ids(red)
    local targets = {}
    local keys, err = red:keys("user:tokens:*")

    if keys and type(keys) == "table" then
        for _, user_tokens_key in ipairs(keys) do
            local email = user_tokens_key:match("^user:tokens:(.+)$")
            
            if email then
                -- ユーザーの全トークンIDを取得
                local token_ids = red:smembers(user_tokens_key)
                
                if token_ids and type(token_ids) == "table" then
                    local orphaned_count = 0
                    
                    for _, token_id in ipairs(token_ids) do
                        -- 対応する token:info: が存在するか確認
                        local token_info_key = "token:info:" .. token_id
                        local exists = red:exists(token_info_key)
                        
                        -- token:info が存在しない場合は孤立トークンID
                        if exists == 0 then
                            table.insert(targets, {
                                user_tokens_key = user_tokens_key,
                                token_id = token_id,
                                user_email = email,
                                reason = "token_info_expired_and_deleted"
                            })
                            orphaned_count = orphaned_count + 1
                        end
                    end
                    
                    -- 全トークンが孤立している場合、空セットとして記録
                    if orphaned_count == #token_ids and #token_ids > 0 then
                        table.insert(targets, {
                            user_tokens_key = user_tokens_key,
                            token_id = nil,
                            user_email = email,
                            reason = "all_tokens_orphaned_empty_set_candidate"
                        })
                    end
                end
                
                -- user:tokens が空のセットかチェック
                local token_count = red:scard(user_tokens_key)
                if token_count == 0 then
                    table.insert(targets, {
                        user_tokens_key = user_tokens_key,
                        token_id = nil,
                        user_email = email,
                        reason = "empty_set"
                    })
                end
            end
        end
    end

    return targets
end

-- 孤立したactive_user_metadata を検索
local function find_orphaned_metadata(red)
    local targets = {}
    local keys, err = red:keys("active_user_metadata:*")

    if keys and type(keys) == "table" then
        for _, metadata_key in ipairs(keys) do
            local email = metadata_key:match("^active_user_metadata:(.+)$")
            
            if email then
                local active_user_key = "active_user:" .. email
                local exists = red:exists(active_user_key)
                
                -- active_userキーが存在しない場合は孤立
                if exists == 0 then
                    table.insert(targets, {
                        key = metadata_key,
                        email = email,
                        reason = "no_active_user"
                    })
                end
            end
        end
    end

    return targets
end

-- クリーンアップログを保存
local function save_cleanup_log(red, log_data)
    local cleanup_id = "cleanup_" .. os.date("%Y%m%d_%H%M%S")
    local log_key = "cleanup:log:" .. cleanup_id
    
    -- ログデータを保存
    red:setex(log_key, LOG_RETENTION_SECONDS, cjson.encode(log_data))
    
    -- ログIDをsorted setに追加（scoreはtimestamp）
    red:zadd("cleanup:logs", log_data.timestamp, cleanup_id)
    
    -- 古いログを削除（保持期間外）
    local cutoff_time = ngx.time() - LOG_RETENTION_SECONDS
    red:zremrangebyscore("cleanup:logs", "-inf", cutoff_time)
    
    return cleanup_id
end

-- クリーンアップ実行（削除明細記録版）
local function execute_cleanup(red, targets, executor_email, is_manual)
    local start_time = ngx.now()
    local results = {
        orphaned_jwt_token_ids_deleted = 0,
        orphaned_metadata_deleted = 0,
        empty_token_sets_deleted = 0
    }
    
    -- ★ 削除明細を記録
    local deleted_items = {}
    
    local processed_sets = {}  -- 重複処理を防ぐ
    
    -- 1. 孤立したJWT Token ID（user:tokens内のゴミ）を削除
    for _, item in ipairs(targets.orphaned_jwt_token_ids or {}) do
        if item.reason == "empty_set" then
            -- 空のセットを削除
            if not processed_sets[item.user_tokens_key] then
                red:del(item.user_tokens_key)
                results.empty_token_sets_deleted = results.empty_token_sets_deleted + 1
                processed_sets[item.user_tokens_key] = true
                
                -- ★ 明細を記録
                table.insert(deleted_items, {
                    type = "empty_token_set",
                    user_email = item.user_email,
                    key = item.user_tokens_key,
                    reason = "empty_set",
                    timestamp = ngx.time()
                })
                
                ngx.log(ngx.INFO, "Cleanup: Deleted empty user:tokens set: ", item.user_tokens_key)
            end
        elseif item.reason == "all_tokens_orphaned_empty_set_candidate" then
            -- 全トークンが孤立している場合は、個別削除後にセット自体も削除
            -- （次の処理で個別削除されるので、ここではマーキングのみ）
        elseif item.token_id then
            -- user:tokens から孤立したトークンIDを削除
            red:srem(item.user_tokens_key, item.token_id)
            results.orphaned_jwt_token_ids_deleted = results.orphaned_jwt_token_ids_deleted + 1
            
            -- ★ 明細を記録
            table.insert(deleted_items, {
                type = "orphaned_jwt_token_id",
                user_email = item.user_email,
                token_id = item.token_id,
                key = item.user_tokens_key,
                reason = item.reason,
                timestamp = ngx.time()
            })
            
            ngx.log(ngx.INFO, "Cleanup: Removed orphaned token ID: ", item.token_id, " from ", item.user_tokens_key)
            
            -- 削除後、セットが空になったかチェック
            local remaining = red:scard(item.user_tokens_key)
            if remaining == 0 and not processed_sets[item.user_tokens_key] then
                red:del(item.user_tokens_key)
                results.empty_token_sets_deleted = results.empty_token_sets_deleted + 1
                processed_sets[item.user_tokens_key] = true
                
                -- ★ 明細を記録
                table.insert(deleted_items, {
                    type = "empty_token_set",
                    user_email = item.user_email,
                    key = item.user_tokens_key,
                    reason = "became_empty_after_cleanup",
                    timestamp = ngx.time()
                })
                
                ngx.log(ngx.INFO, "Cleanup: Deleted now-empty user:tokens set: ", item.user_tokens_key)
            end
        end
    end
    
    -- 2. 孤立したmetadataを削除
    for _, item in ipairs(targets.orphaned_metadata or {}) do
        red:del(item.key)
        results.orphaned_metadata_deleted = results.orphaned_metadata_deleted + 1
        
        -- ★ 明細を記録
        table.insert(deleted_items, {
            type = "orphaned_metadata",
            user_email = item.email,
            key = item.key,
            reason = item.reason,
            timestamp = ngx.time()
        })
        
        ngx.log(ngx.INFO, "Cleanup: Deleted orphaned metadata: ", item.key)
    end
    
    -- 合計
    local total_deleted = results.orphaned_jwt_token_ids_deleted 
                        + results.orphaned_metadata_deleted
                        + results.empty_token_sets_deleted
    
    local duration_ms = math.floor((ngx.now() - start_time) * 1000)
    
    -- ログデータを作成（削除明細を含む）
    local log_data = {
        timestamp = ngx.time(),
        executed_by = executor_email,
        manual = is_manual,
        results = results,
        total_deleted = total_deleted,
        duration_ms = duration_ms,
        freed_memory = estimate_memory_size(total_deleted),
        deleted_items = deleted_items  -- ★ 削除明細を追加
    }
    
    -- ログを保存
    local cleanup_id = save_cleanup_log(red, log_data)
    
    return cleanup_id, log_data
end

-- OAuth2認証チェック
local email_header = ngx.var.http_x_forwarded_email

-- Cron実行の場合は特別扱い
local is_cron = (email_header == "cron@system")

if not is_cron then
    if not email_header or email_header == "" then
        send_response(401, {error = "Authentication required"})
    end

    -- 管理者チェック
    if not is_admin(email_header) then
        send_response(403, {error = "Admin access only", user = email_header})
    end
end

-- Redis接続
local red, err = connect_redis()
if not red then
    send_response(500, {error = "Redis connection failed", message = err})
end

-- リクエストメソッド処理
local method = ngx.req.get_method()
local uri = ngx.var.uri

-- GET /api/admin/redis/cleanup/preview - プレビュー（削除せずに表示のみ）
if method == "GET" and uri == "/api/admin/redis/cleanup/preview" then
    local targets = {
        orphaned_jwt_token_ids = find_orphaned_jwt_token_ids(red),
        orphaned_metadata = find_orphaned_metadata(red)
    }
    
    local counts = {
        orphaned_jwt_token_ids = #targets.orphaned_jwt_token_ids,
        orphaned_metadata = #targets.orphaned_metadata,
        total = #targets.orphaned_jwt_token_ids + #targets.orphaned_metadata
    }
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        preview = true,
        targets = targets,
        counts = counts,
        estimated_freed_memory = estimate_memory_size(counts.total),
        config = {
            log_retention_days = CLEANUP_LOG_RETENTION_DAYS
        },
        note = {
            auto_deleted_by_ttl = {
                "token:info:* - Deleted by TTL when token expires",
                "revoked:token:* - Deleted by TTL when original token expires",
                "active_user_deleted:* - Deleted by TTL after 7 days",
                "_oauth2_proxy* - Deleted by TTL when session expires"
            },
            manual_cleanup_needed = {
                "user:tokens:* - Orphaned token IDs remain after token:info expires",
                "active_user_metadata:* - Orphaned when active_user is deleted"
            }
        }
    })

-- POST /api/admin/redis/cleanup - クリーンアップ実行
elseif method == "POST" and uri == "/api/admin/redis/cleanup" then
    -- ターゲットを検索
    local targets = {
        orphaned_jwt_token_ids = find_orphaned_jwt_token_ids(red),
        orphaned_metadata = find_orphaned_metadata(red)
    }
    
    -- クリーンアップ実行（削除明細付き）
    local cleanup_id, log_data = execute_cleanup(red, targets, email_header, not is_cron)
    
    red:set_keepalive(10000, 100)
    
    ngx.log(ngx.INFO, "Redis cleanup completed: ", cleanup_id, " by ", email_header, " (", log_data.total_deleted, " items deleted)")
    
    send_response(200, {
        cleanup_id = cleanup_id,
        executed_at = log_data.timestamp,
        executed_by = log_data.executed_by,
        manual = log_data.manual,
        results = log_data.results,
        total_deleted = log_data.total_deleted,
        freed_memory = log_data.freed_memory,
        duration_ms = log_data.duration_ms,
        deleted_items = log_data.deleted_items  -- ★ 削除明細を返す
    })

-- GET /api/admin/redis/cleanup/logs - クリーンアップログ一覧
elseif method == "GET" and uri == "/api/admin/redis/cleanup/logs" then
    -- ログIDを取得（新しい順）
    local log_ids, err = red:zrevrange("cleanup:logs", 0, 99)  -- 最新100件
    
    local logs = {}
    
    if log_ids and type(log_ids) == "table" then
        for _, cleanup_id in ipairs(log_ids) do
            local log_key = "cleanup:log:" .. cleanup_id
            local log_json = red:get(log_key)
            
            if log_json and log_json ~= ngx.null then
                local ok, log_data = pcall(cjson.decode, log_json)
                if ok then
                    table.insert(logs, {
                        cleanup_id = cleanup_id,
                        timestamp = log_data.timestamp,
                        executed_by = log_data.executed_by,
                        manual = log_data.manual,
                        total_deleted = log_data.total_deleted,
                        freed_memory = log_data.freed_memory,
                        duration_ms = log_data.duration_ms,
                        results = log_data.results,
                        deleted_items = log_data.deleted_items  -- ★ 削除明細を含む
                    })
                end
            end
        end
    end
    
    red:set_keepalive(10000, 100)
    
    send_response(200, {
        logs = logs,
        total_logs = #logs,
        retention_days = CLEANUP_LOG_RETENTION_DAYS
    })

else
    red:set_keepalive(10000, 100)
    send_response(405, {error = "Method not allowed"})
end
