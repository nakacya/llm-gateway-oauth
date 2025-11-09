# nginx.conf 未使用エンドポイント分析レポート

**分析日**: 2025年11月10日  
**対象**: nginx.conf v11.1

---

## 🔍 発見された未使用・問題のあるエンドポイント

### 1. ⚠️ Port 8080の古いトークン管理API（4エンドポイント）

**場所**: Port 8080 (内部処理サーバー)  
**ステータス**: 使用されていない可能性が高い

| エンドポイント | 行番号 | 参照Luaファイル | 問題 |
|--------------|--------|----------------|------|
| `/api/token/generate` | 379 | token_generator.lua | 古いAPI、/key/generate に置き換え済み |
| `/api/token/info` | 383 | token_info.lua | 古いAPI、/api/admin/tokens で代替 |
| `/api/token/revoke` | 387 | token_revoke.lua | 古いAPI、DELETE /api/admin/tokens/{id} で代替 |
| `/api/token/list` | 391 | token_list.lua | 古いAPI、GET /api/admin/tokens で代替 |

**現在使用されているAPI**:
- ✅ `/key/generate` (LiteLLM統合、Phase 4.3で検証済み)
- ✅ `/api/admin/tokens` (RESTful API、Phase 4で検証済み)

**推奨アクション**: 削除候補

---

### 2. ⚠️ Port 80の /api/token/ エンドポイント

**場所**: Port 80 (外部公開サーバー)  
**行番号**: 293  
**ステータス**: 機能していない可能性が高い

**問題点**:
```nginx
location /api/token/ {
    auth_request /oauth2/auth;
    # ...
    proxy_pass http://oauth2_proxy_backend;  # ← OAuth2 Proxyへプロキシ
}
```

- OAuth2 Proxyは `/api/token/*` エンドポイントを持っていない
- アクセスすると404エラーになる可能性が高い
- Phase 3の検証で「Token API context」がスキップされた理由

**推奨アクション**: 削除候補

---

### 3. ❓ /token-manager エンドポイント（重複の可能性）

**場所**: Port 8080 (内部処理サーバー)  
**行番号**: 541  
**ステータス**: 古い管理画面の可能性

```nginx
location /token-manager {
    default_type text/html;
    alias /usr/local/openresty/nginx/html/token_manager.html;
    access_by_lua_file /usr/local/openresty/lualib/custom/oauth_check.lua;
}
```

**現在使用されている管理画面**:
```nginx
location = /token-session-manager {
    default_type text/html;
    alias /usr/local/openresty/nginx/html/token_session_manager.html;
    access_by_lua_file /usr/local/openresty/lualib/custom/oauth_check.lua;
}
```

- Phase 2.2で `/token-session-manager` が正常動作確認済み
- `/token-manager` が実際に使用されているか不明

**推奨アクション**: 使用状況を確認してから判断

---

## 📊 エンドポイント使用状況サマリー

### 使用中 ✅

| エンドポイント | 用途 | 検証済み |
|--------------|------|---------|
| `/api/admin/tokens` | トークン管理（RESTful） | Phase 4 |
| `/api/admin/sessions` | セッション管理（RESTful） | Phase 6 |
| `/key/generate` | トークン生成（LiteLLM） | Phase 4.3 |
| `/token-session-manager` | 統合管理画面 | Phase 2.2 |
| `/v1/messages` | LLM API | Phase 5.1 |
| `/health` | ヘルスチェック | Phase 1.3, 7.2 |

### 未使用の可能性 ⚠️

| エンドポイント | 理由 |
|--------------|------|
| `/api/token/generate` | 古いAPI、/key/generate で代替 |
| `/api/token/info` | 古いAPI、RESTful APIで代替 |
| `/api/token/revoke` | 古いAPI、RESTful APIで代替 |
| `/api/token/list` | 古いAPI、RESTful APIで代替 |
| Port 80の `/api/token/` | OAuth2 Proxyに機能なし |

### 要確認 ❓

| エンドポイント | 確認事項 |
|--------------|---------|
| `/token-manager` | 実際に使用されているか |

---

## 🎯 推奨される対応

### オプション1: 段階的削除（推奨）

#### Step 1: アクセスログで使用状況を確認
```bash
# 過去1週間のアクセスログを確認
sudo docker compose logs --since 168h openresty | grep -E "/api/token/|/token-manager"
```

#### Step 2: 未使用が確認できたらコメントアウト
```nginx
# 古いトークン管理API（削除予定）
#X# location = /api/token/generate {
#X#     content_by_lua_file /usr/local/openresty/lualib/custom/token_generator.lua;
#X# }
```

#### Step 3: 2週間運用して問題なければ削除

---

### オプション2: 即座に削除

以下のエンドポイントは明らかに未使用のため、即座に削除可能：

1. **Port 8080の古いトークン管理API** (4エンドポイント)
   - `/api/token/generate`
   - `/api/token/info`
   - `/api/token/revoke`
   - `/api/token/list`
   - 対応するLuaファイルも削除

2. **Port 80の `/api/token/`**
   - OAuth2 Proxyにプロキシしているが機能しない

---

## 💾 バックアップ方針

削除前に必ずバックアップを作成：

```bash
cd ~/oauth2
cp nginx.conf nginx.conf.backup_before_cleanup_$(date +%Y%m%d)

# Luaファイルもバックアップ
cd lua
tar -czf ../lua_backup_before_cleanup_$(date +%Y%m%d).tar.gz *.lua
```

---

## 📝 関連ファイル

削除候補のLuaファイル：
- `lua/token_generator.lua`
- `lua/token_info.lua`
- `lua/token_revoke.lua`
- `lua/token_list.lua`

削除候補のHTMLファイル（要確認）：
- `token_manager.html` ※ `/token-session-manager` が使用されている場合

---

## ⚠️ 注意事項

1. **削除前に必ずアクセスログを確認**
2. **バックアップを作成**
3. **段階的に削除（コメントアウト → 運用確認 → 削除）**
4. **削除後は動作確認を実施**

---

**作成者**: Claude (Sonnet 4.5)  
**作成日**: 2025年11月10日
