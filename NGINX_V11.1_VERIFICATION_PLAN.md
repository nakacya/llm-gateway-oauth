# nginx.conf v11.1 検証計画書

**作成日**: 2025年11月08日  
**バージョン**: nginx.conf v11.1 (整理版)  
**目的**: アクティブユーザー追跡の関数化、ログレベル変更、upstream最適化の動作検証

---

## 📋 変更内容サマリー

| 項目 | v10 | v11.1 | 影響範囲 |
|------|-----|-------|----------|
| ログレベル | `debug` | `warn` | エラーログの出力量 |
| アクティブユーザー追跡 | 各locationで重複実装 | `_G.track_user` 関数化 | 5箇所のlocation |
| upstream設定 | keepalive 32 | keepalive 32 + requests/timeout | 接続効率 |
| デバッグコード | 保持 | 保持 | トラブルシューティング |

---

## 🎯 検証目標

1. **機能の正常動作**: 全ての既存機能が正常に動作すること
2. **新機能の動作**: `_G.track_user` 関数が正しく動作すること
3. **ログ出力**: ログレベル変更後も必要な情報が記録されること
4. **パフォーマンス**: upstream最適化の効果を確認すること
5. **後方互換性**: 既存のAPI/UIが影響を受けないこと

---

## 📝 検証項目一覧

### Phase 1: 基本動作確認（必須）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 1.1 | 構文チェック | 最高 | 1分 |
| 1.2 | コンテナ再起動 | 最高 | 2分 |
| 1.3 | ヘルスチェック | 最高 | 1分 |
| 1.4 | エラーログ確認 | 最高 | 2分 |

### Phase 2: OAuth2認証フロー（必須）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 2.1 | OAuth2ログイン | 最高 | 3分 |
| 2.2 | 管理画面アクセス | 最高 | 2分 |
| 2.3 | ログアウト | 高 | 2分 |

### Phase 3: アクティブユーザー追跡（最重要）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 3.1 | MCP/Internal追跡 | 最高 | 3分 |
| 3.2 | UI/Admin追跡 | 最高 | 3分 |
| 3.3 | Key Management追跡 | 最高 | 3分 |
| 3.4 | Token API追跡 | 最高 | 3分 |
| 3.5 | Default追跡 | 最高 | 3分 |
| 3.6 | ログ出力確認（context付き） | 最高 | 5分 |

### Phase 4: トークン管理機能（必須）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 4.1 | JWT トークン生成 | 最高 | 3分 |
| 4.2 | トークン一覧取得 | 高 | 2分 |
| 4.3 | トークン情報取得 | 高 | 2分 |
| 4.4 | トークン失効 | 高 | 2分 |

### Phase 5: LLM API（必須）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 5.1 | /v1/messages (JWT認証) | 最高 | 5分 |
| 5.2 | ユーザー情報の付与確認 | 高 | 3分 |

### Phase 6: Session管理・BAN機能（重要）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 6.1 | アクティブユーザー一覧取得 | 高 | 2分 |
| 6.2 | 即時BAN機能 | 高 | 3分 |
| 6.3 | BAN中の再認証防止 | 高 | 3分 |
| 6.4 | BAN解除機能 | 高 | 2分 |

### Phase 7: パフォーマンス確認（推奨）

| No | 検証項目 | 優先度 | 所要時間 |
|----|----------|--------|----------|
| 7.1 | upstream接続確認 | 中 | 5分 |
| 7.2 | レスポンスタイム測定 | 中 | 5分 |

---

## 🔍 詳細検証手順

### Phase 1: 基本動作確認

#### 1.1 構文チェック ✅（完了済み）

```bash
sudo docker compose cp nginx_v11.1.conf openresty:/tmp/nginx_v11.1.conf
sudo docker compose exec openresty openresty -t -c /tmp/nginx_v11.1.conf
```

**期待結果**:
```
nginx: the configuration file /tmp/nginx_v11.1.conf syntax is ok
nginx: configuration file /tmp/nginx_v11.1.conf test is successful
```

---

#### 1.2 コンテナ再起動

**前提条件**: バックアップ作成済み

```bash
# 1. バックアップ作成
sudo docker compose exec openresty cp \
  /usr/local/openresty/nginx/conf/nginx.conf \
  /usr/local/openresty/nginx/conf/nginx.conf.backup_v10_20251108

# 2. 新しいnginx.confを配置
cd ~/oauth2
sudo docker compose cp nginx_v11.1.conf openresty:/usr/local/openresty/nginx/conf/nginx.conf

# 3. 再起動
sudo docker compose restart openresty
```

**期待結果**:
```
[+] Restarting 1/1
 ✔ Container oauth2-openresty-1  Started
```

**失敗時の対応**:
```bash
# ログ確認
sudo docker compose logs --tail=50 openresty

# ロールバック
sudo docker compose exec openresty cp \
  /usr/local/openresty/nginx/conf/nginx.conf.backup_v10_20251108 \
  /usr/local/openresty/nginx/conf/nginx.conf
sudo docker compose restart openresty
```

---

#### 1.3 ヘルスチェック

```bash
curl -s http://localhost:8080/health | jq .
```

**期待結果**:
```json
{
  "status": "healthy"
}
```

**失敗時の対応**:
- コンテナログを確認: `sudo docker compose logs openresty`
- ロールバック実施

---

#### 1.4 エラーログ確認

```bash
# エラーログの最新50行を確認
sudo docker compose logs --tail=50 openresty | grep -i "error\|warn\|failed"
```

**期待結果**:
- `[error]` レベルのログが無いこと
- `[warn]` レベルのログは許容（ログレベル変更により出力される）
- 起動時のエラーが無いこと

**確認ポイント**:
- ✅ Lua関数 `_G.track_user` の初期化成功
- ✅ upstream 接続成功
- ✅ 致命的なエラーなし

---

### Phase 2: OAuth2認証フロー

#### 2.1 OAuth2ログイン

**手順**:
1. ブラウザで https://litellm.nakacya.jp にアクセス
2. Auth0ログイン画面にリダイレクトされることを確認
3. nakacya@gmail.com でログイン
4. トップページまたはダッシュボードが表示されること

**期待結果**:
- ✅ Auth0ログイン画面が表示される
- ✅ ログイン成功後、元のページにリダイレクトされる
- ✅ OAuth2 Cookie `_oauth2_proxy` が設定される

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "track_user"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [Default]
[info] User tracking success: nakacya@gmail.com
```

---

#### 2.2 管理画面アクセス

**手順**:
1. https://litellm.nakacya.jp/token-session-manager にアクセス
2. 管理画面が表示されることを確認

**期待結果**:
- ✅ 管理画面が正常に表示される
- ✅ 401エラーにならない

**ログ確認**:
```bash
sudo docker compose logs --tail=50 openresty | grep "token-session-manager"
```

---

#### 2.3 ログアウト

**手順**:
1. https://litellm.nakacya.jp/oauth2/sign_out にアクセス
2. ログアウトされることを確認

**期待結果**:
- ✅ ログアウト成功
- ✅ 再度アクセスするとAuth0ログイン画面が表示される

---

### Phase 3: アクティブユーザー追跡（最重要）

この検証では、`_G.track_user` 関数が5箇所全てで正しく動作することを確認します。

#### 3.1 MCP/Internal追跡

**手順**:
```bash
# ログイン済みのブラウザで以下にアクセス
# https://litellm.nakacya.jp/v1/internal/info (存在する場合)
```

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "MCP/Internal"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [MCP/Internal]
[info] User tracking success: nakacya@gmail.com
```

**確認ポイント**:
- ✅ context に `[MCP/Internal]` が含まれる
- ✅ 追跡成功ログが出力される

---

#### 3.2 UI/Admin追跡

**手順**:
```bash
# ログイン済みのブラウザで以下にアクセス
# https://litellm.nakacya.jp/ui/
# または
# https://litellm.nakacya.jp/admin/
```

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "UI/Admin"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [UI/Admin]
[info] User tracking success: nakacya@gmail.com
```

---

#### 3.3 Key Management追跡

**手順**:
```bash
# ログイン済みのブラウザで以下にアクセス
# https://litellm.nakacya.jp/key/info (存在する場合)
```

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "Key Management"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [Key Management]
[info] User tracking success: nakacya@gmail.com
```

---

#### 3.4 Token API追跡

**手順**:
```bash
# ログイン済みのブラウザで以下にアクセス
# https://litellm.nakacya.jp/api/token/ (存在する場合)
```

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "Token API"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [Token API]
[info] User tracking success: nakacya@gmail.com
```

---

#### 3.5 Default追跡

**手順**:
```bash
# ログイン済みのブラウザで以下にアクセス
# https://litellm.nakacya.jp/
```

**ログ確認**:
```bash
sudo docker compose logs --tail=100 openresty | grep "Default"
```

**期待ログ**:
```
[info] Tracking user: nakacya@gmail.com [Default]
[info] User tracking success: nakacya@gmail.com
```

---

#### 3.6 ログ出力確認（context付き）

**全体ログ確認**:
```bash
# 最新200行から追跡ログを抽出
sudo docker compose logs --tail=200 openresty | grep -E "Tracking user|User tracking"
```

**期待結果**:
全ての追跡ログに以下の形式でcontextが含まれること:
```
[info] Tracking user: <email> [<context>]
[info] User tracking success: <email>
```

**contextの種類**:
- `[MCP/Internal]`
- `[UI/Admin]`
- `[Key Management]`
- `[Token API]`
- `[Default]`

**確認ポイント**:
- ✅ 全てのcontextで追跡が成功している
- ✅ `User tracking failed` ログがない（または許容範囲内）
- ✅ ログが重複していない（関数化により整理されている）

---

### Phase 4: トークン管理機能

#### 4.1 JWT トークン生成

**手順**:
1. https://litellm.nakacya.jp/token-session-manager にアクセス
2. 「トークン生成」セクションで新しいトークンを生成

**期待結果**:
- ✅ トークン生成成功
- ✅ トークンIDが表示される
- ✅ エラーが発生しない

**APIテスト**:
```bash
# OAuth2 Cookie を取得してAPI呼び出し
# （ブラウザのDevToolsからCookieをコピー）

curl -X POST http://localhost/api/admin/tokens \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "generate",
    "token_name": "test-token-v11.1",
    "duration": 30,
    "models": ["claude-sonnet-4-20250514"]
  }'
```

---

#### 4.2 トークン一覧取得

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/tokens \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{"action": "list"}'
```

**期待結果**:
- ✅ トークン一覧がJSON形式で返される
- ✅ 生成したトークンが含まれる

---

#### 4.3 トークン情報取得

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/tokens \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "info",
    "token_id": "<token_id>"
  }'
```

**期待結果**:
- ✅ トークン詳細情報が返される
- ✅ email、有効期限などが含まれる

---

#### 4.4 トークン失効

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/tokens \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "revoke",
    "token_id": "<token_id>"
  }'
```

**期待結果**:
- ✅ トークン失効成功
- ✅ 失効後、そのトークンでAPI呼び出しができない

---

### Phase 5: LLM API

#### 5.1 /v1/messages (JWT認証)

**手順**:
1. Phase 4.1で生成したトークンを使用
2. LLM APIを呼び出し

**APIテスト**:
```bash
curl -X POST http://localhost/v1/messages \
  -H "Authorization: Bearer <jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [
      {"role": "user", "content": "Hello, this is a test for nginx v11.1"}
    ]
  }'
```

**期待結果**:
- ✅ 正常にレスポンスが返される
- ✅ 401エラーにならない
- ✅ Claudeからの応答が含まれる

---

#### 5.2 ユーザー情報の付与確認

**ログ確認**:
```bash
sudo docker compose logs --tail=100 litellm | grep "nakacya@gmail.com"
```

**期待結果**:
- ✅ LiteLLMのログにユーザー情報が含まれる
- ✅ `X-LiteLLM-User-Email` ヘッダーが正しく渡されている

---

### Phase 6: Session管理・BAN機能

#### 6.1 アクティブユーザー一覧取得

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/sessions \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{"action": "list_active"}'
```

**期待結果**:
- ✅ アクティブユーザー一覧が返される
- ✅ nakacya@gmail.com が含まれる
- ✅ 最終アクセス時刻が更新されている

---

#### 6.2 即時BAN機能

**テストユーザー**: `nakacya+test@gmail.com` (存在する場合)

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/sessions \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "delete_immediate",
    "email": "nakacya+test@gmail.com",
    "ban_duration_days": 7
  }'
```

**期待結果**:
- ✅ BAN成功
- ✅ Redis に `active_user_deleted:nakacya+test@gmail.com` が作成される

**Redis確認**:
```bash
sudo docker compose exec redis redis-cli
> GET active_user_deleted:nakacya+test@gmail.com
```

---

#### 6.3 BAN中の再認証防止

**手順**:
1. BAN済みユーザー `nakacya+test@gmail.com` でログインを試みる
2. ログインできないことを確認

**期待結果**:
- ✅ ログイン後すぐにログアウトされる
- ✅ またはエラーメッセージが表示される

---

#### 6.4 BAN解除機能

**APIテスト**:
```bash
curl -X POST http://localhost/api/admin/sessions \
  -H "Cookie: _oauth2_proxy=<cookie_value>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "unban",
    "email": "nakacya+test@gmail.com"
  }'
```

**期待結果**:
- ✅ BAN解除成功
- ✅ Redis の `active_user_deleted:nakacya+test@gmail.com` が削除される

**Redis確認**:
```bash
sudo docker compose exec redis redis-cli
> GET active_user_deleted:nakacya+test@gmail.com
(nil)
```

---

### Phase 7: パフォーマンス確認

#### 7.1 upstream接続確認

**手順**:
```bash
# netstat でkeepalive接続を確認
sudo docker compose exec openresty netstat -an | grep 8080 | grep ESTABLISHED
```

**期待結果**:
- ✅ 127.0.0.1:8080 への接続が維持されている（keepalive）
- ✅ 接続数が適切な範囲内（32以下）

---

#### 7.2 レスポンスタイム測定

**手順**:
```bash
# 10回連続でヘルスチェックを実行してレスポンスタイムを測定
for i in {1..10}; do
  time curl -s http://localhost:8080/health > /dev/null
done
```

**期待結果**:
- ✅ レスポンスタイムが安定している
- ✅ v10と比較して遅延がない（または改善されている）

---

## 🚨 トラブルシューティング

### 問題1: `_G.track_user` 関数が見つからない

**症状**:
```
[error] attempt to call global 'track_user' (a nil value)
```

**原因**: `init_by_lua_block` で関数が定義されていない

**対応**:
1. nginx.confの `init_by_lua_block` セクションを確認
2. `_G.track_user` 関数が正しく定義されているか確認
3. 構文エラーがないか確認

---

### 問題2: アクティブユーザー追跡が失敗する

**症状**:
```
[warn] User tracking failed: nakacya@gmail.com status: 500
```

**原因**: Port 8080の `/track_user_internal` エンドポイントエラー

**対応**:
```bash
# active_user_tracker.luaのログを確認
sudo docker compose logs --tail=100 openresty | grep "active_user_tracker"

# Redisの接続を確認
sudo docker compose exec redis redis-cli PING
```

---

### 問題3: OAuth2認証が失敗する

**症状**: ログイン後、401エラーが表示される

**原因**: OAuth2 Proxyとの連携問題

**対応**:
```bash
# OAuth2 Proxyのログを確認
sudo docker compose logs --tail=100 oauth2-proxy

# nginx.confのOAuth2設定を確認
sudo docker compose exec openresty cat /usr/local/openresty/nginx/conf/nginx.conf | grep -A 10 "oauth2/auth"
```

---

### 問題4: upstream接続エラー

**症状**:
```
[error] connect() failed (111: Connection refused) while connecting to upstream
```

**原因**: Port 8080が起動していない、またはupstream設定エラー

**対応**:
```bash
# Port 8080のリスニング確認
sudo docker compose exec openresty netstat -tuln | grep 8080

# upstream設定を確認
sudo docker compose exec openresty cat /usr/local/openresty/nginx/conf/nginx.conf | grep -A 5 "upstream openresty_internal"
```

---

## 🔄 ロールバック手順

問題が発生した場合、以下の手順でv10にロールバックします。

```bash
# 1. バックアップからリストア
sudo docker compose exec openresty cp \
  /usr/local/openresty/nginx/conf/nginx.conf.backup_v10_20251108 \
  /usr/local/openresty/nginx/conf/nginx.conf

# 2. 構文チェック
sudo docker compose exec openresty openresty -t

# 3. 再起動
sudo docker compose restart openresty

# 4. ヘルスチェック
curl -s http://localhost:8080/health | jq .

# 5. ログ確認
sudo docker compose logs --tail=50 openresty
```

---

## ✅ 検証完了チェックリスト

### 必須項目（Phase 1-4）

- [ ] 1.1 構文チェック成功
- [ ] 1.2 コンテナ再起動成功
- [ ] 1.3 ヘルスチェック成功
- [ ] 1.4 エラーログに致命的なエラーなし
- [ ] 2.1 OAuth2ログイン成功
- [ ] 2.2 管理画面アクセス成功
- [ ] 3.1 MCP/Internal追跡成功（ログ確認）
- [ ] 3.2 UI/Admin追跡成功（ログ確認）
- [ ] 3.3 Key Management追跡成功（ログ確認）
- [ ] 3.4 Token API追跡成功（ログ確認）
- [ ] 3.5 Default追跡成功（ログ確認）
- [ ] 3.6 全てのcontextでログ出力確認
- [ ] 4.1 JWT トークン生成成功
- [ ] 4.2 トークン一覧取得成功
- [ ] 4.4 トークン失効成功

### 重要項目（Phase 5-6）

- [ ] 5.1 /v1/messages API呼び出し成功
- [ ] 5.2 ユーザー情報付与確認
- [ ] 6.1 アクティブユーザー一覧取得成功
- [ ] 6.2 即時BAN機能成功
- [ ] 6.3 BAN中の再認証防止確認
- [ ] 6.4 BAN解除機能成功

### 推奨項目（Phase 7）

- [ ] 7.1 upstream接続確認
- [ ] 7.2 レスポンスタイム測定

---

## 📊 検証結果レポート

検証完了後、以下のフォーマットで結果をまとめてください。

### 検証サマリー

| Phase | 項目数 | 成功 | 失敗 | スキップ |
|-------|--------|------|------|----------|
| Phase 1: 基本動作 | 4 | - | - | - |
| Phase 2: OAuth2 | 3 | - | - | - |
| Phase 3: ユーザー追跡 | 6 | - | - | - |
| Phase 4: トークン管理 | 4 | - | - | - |
| Phase 5: LLM API | 2 | - | - | - |
| Phase 6: Session/BAN | 4 | - | - | - |
| Phase 7: パフォーマンス | 2 | - | - | - |

### 検出された問題

| No | 問題内容 | 重大度 | 対応状況 |
|----|----------|--------|----------|
| - | - | - | - |

### 総合評価

- [ ] **合格**: 全ての必須項目が成功し、本番デプロイ可能
- [ ] **条件付き合格**: 一部の問題があるが、本番デプロイ可能（問題の記録が必要）
- [ ] **不合格**: 致命的な問題があり、ロールバックが必要

---

## 📅 検証スケジュール

| 日時 | Phase | 担当 | 所要時間 |
|------|-------|------|----------|
| 2025/11/08 | Phase 1 | nakacya | 10分 |
| 2025/11/08 | Phase 2-3 | nakacya | 30分 |
| 2025/11/08 | Phase 4-6 | nakacya | 30分 |
| 2025/11/08 | Phase 7（推奨） | nakacya | 10分 |

**合計所要時間**: 約60-90分

---

## 📝 備考

- この検証計画書は、nginx.conf v11.1の動作確認に特化しています
- 検証は本番環境で実施するため、バックアップとロールバック手順を必ず確認してください
- 問題が発生した場合は、速やかにロールバックし、原因を調査してください
- 全ての検証項目を完了する必要はありませんが、Phase 1-4の必須項目は必ず実施してください

---

**作成者**: Claude (Sonnet 4.5)  
**作成日**: 2025年11月08日  
**バージョン**: 1.0
