# LiteLLM Gateway with OAuth2 + JWT認証

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://www.docker.com/)
[![Auth0](https://img.shields.io/badge/Auth-Auth0-EB5424?logo=auth0)](https://auth0.com/)

> OAuth2認証とJWTトークン管理を備えた、チームでの安全なLLM利用のためのエンタープライズグレードAPIゲートウェイ

[English README is here](README.md)

---

## 🌟 主な機能

- **🔐 二重認証システム**
  - ブラウザアクセス用のOAuth2認証（Auth0）
  - API/CLIクライアント用のJWTトークン（最大90日間有効）

- **🛡️ セキュリティ強化**
  - ユーザー削除時の即時トークン無効化
  - Redisベースのトークンブラックリスト管理
  - **強制ログアウト機能付きセッション削除**
  - **即時BAN機能（7日間強制ログアウト）** - OAuth2とJWT token両方に対応（NEW）
  - OAuth2セッションチェック（実装予定：毎日再認証）

- **📊 完全な可観測性**
  - Langfuseによるリアルタイムトレーシング
  - ユーザー別使用状況分析（全APIリクエストにOAuth2メールアドレスを付与）
  - モデル/ユーザー別コスト追跡
  - ユーザー個別の予算制限設定が可能

- **🔄 トークン・セッション管理**
  - **4タブ統合管理ダッシュボード**（NEW）
  - ユーザーごとに複数トークン発行可能
  - カスタム有効期限設定
  - **リアルタイムセッション監視**
  - **アクティブユーザー追跡とBAN管理** - OAuth2とJWT token統合管理（NEW）
  - **強制ログアウト機能**

- **🧹 Redisクリーンアップ**（NEW）
  - 孤立トークンの自動クリーンアップ
  - **詳細削除監査ログと展開可能な明細**（NEW）
  - 手動・スケジュールクリーンアップ対応
  - メモリ使用量の最適化
  - 30日間のログ保持

- **🚀 本番環境対応**
  - Docker Composeによる簡単デプロイ
  - OpenResty + LiteLLMアーキテクチャ
  - PostgreSQL、Redis、ClickHouse統合

---

## 🏗️ アーキテクチャ
```
┌─────────────┐
│   Client    │ (ブラウザ/Roo Code/CLI)
│  (ユーザー)  │
└──────┬──────┘
       │ OAuth2 / JWT
       ↓
┌──────────────────────────────────────┐
│         OpenResty (ゲートウェイ)      │
│  - JWT検証 + BAN状態チェック          │
│  - OAuth2セッションチェック           │
│  - Active User追跡                   │
│  - リクエストルーティング             │
└──────┬───────────┬───────────────────┘
       │           │
       │           └──────────┐
       │                      ↓
       │                ┌──────────┐
       │                │  Redis   │
       │                │(トークン  │
       │                │ セッション│
       │                │ BAN状態) │
       │                └──────────┘
       │
    ┌──┴─────────────────┐
    │                    │
    ↓                    ↓
┌──────────────┐    ┌──────────────┐
│ OAuth2 Proxy │    │   LiteLLM    │
│   (Auth0)    │    │    Proxy     │
└──────────────┘    └──────┬───────┘
                           │
                    ┌──────┴─────┐
                    ↓            ↓
              ┌──────────┐  ┌──────────┐
              │ Langfuse │  │ Claude   │
              │(トレース)│  │   API    │
              └──────────┘  └──────────┘
```

---

## 📋 前提条件

- Docker & Docker Compose v2
- Auth0アカウント（無料プランあり）
- Anthropic APIキー
- Ubuntu 24.04または同等のLinuxディストリビューション

---

## 🚀 クイックスタート

### 1. リポジトリのクローン
```bash
git clone https://github.com/nakacya/llm-gateway-oauth.git
cd llm-gateway-oauth
```

### 2. 環境変数の設定
```bash
# サンプル設定をコピー
cp .env_sample .env
cp oauth2_proxy.cfg.sample oauth2_proxy.cfg
cp litellm_config.yaml.sample litellm_config.yaml

# 認証情報を編集
vi .env
vi oauth2_proxy.cfg
vi litellm_config.yaml
```

**`.env`の必須設定**:
```bash
# Auth0設定
AUTH0_DOMAIN=your-tenant.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret

# JWTシークレット（生成: openssl rand -base64 64）
JWT_SECRET=your_generated_secret

# Cookieシークレット（生成方法は.env_sampleを参照）
OAUTH2_PROXY_COOKIE_SECRET=your_cookie_secret

# APIキー
ANTHROPIC_API_KEY=sk-ant-your-api-key
```

### 3. Auth0の設定

1. Auth0ダッシュボードでアプリケーションを作成
2. Application Type: **Regular Web Application** を選択
3. URLを設定:
   - **Allowed Callback URLs**: `http://{your-fqdn}/oauth2/callback`
   - **Allowed Logout URLs**: `http://{your-fqdn}`
   - **Allowed Web Origins**: `http://{your-fqdn}`

`{your-fqdn}`は実際のドメインに置き換えてください（例：`localhost`、`litellm.example.com`）

### 4. カスタムOpenRestyイメージのビルド
```bash
# 必要なモジュールを含むOpenRestyをビルド
sudo docker compose build openresty

# 以下が実行されます:
# - lua-resty-jwtのインストール
# - Luaモジュールの設定
# - カスタムOpenResty環境のセットアップ
```

### 5. サービスの起動
```bash
# 全コンテナを起動
sudo docker compose up -d

# 全コンテナが起動していることを確認
sudo docker compose ps
```

### 6. インストール確認
```bash
# 全コンテナが起動していることを確認
sudo docker compose ps

# ゲートウェイにアクセス
open http://{your-fqdn}

# またはcurlを使用
curl -I http://{your-fqdn}
```

---

## 📖 使用方法

### ブラウザアクセス

1. `http://{your-fqdn}` にアクセス
2. Auth0経由でログイン
3. `http://{your-fqdn}/token-session-manager` でToken & Session Managerにアクセス
4. 統合Web UIからJWTトークン、セッション、アクティブユーザー、Redisクリーンアップを管理

**利用可能なUI**:
- **Token Manager** (`/token-manager`): APIトークンの生成と管理
- **Token & Session Manager** (`/token-session-manager`): リアルタイム監視機能を備えた4タブ統合管理ダッシュボード（管理者のみ）
- **Admin Manager** (`/admin-manager`): ユーザー管理用の管理パネル（管理者のみ）

### Token & Session Manager の機能（4タブダッシュボード）

統合管理インターフェースで包括的な制御を提供:

**👥 Active Usersタブ**（NEW）:
- **OAuth2とJWT token両方のユーザーを統合表示**
- 全アクティブユーザーとセッション/トークン数の表示
- 認証方法の識別（OAuth2 / JWT）
- 最終アクセス時刻と有効期限の追跡
- **即時BAN機能**（7日間強制ログアウト）- すべてのアクセス経路に適用
- **必要に応じたBAN解除**
- BAN残り時間の表示
- 統計ダッシュボード（総ユーザー数、BANユーザー数）
- メールアドレスによるユーザー検索
- 期限切れユーザーデータのクリーンアップ

**🔐 Sessionsタブ**:
- 全アクティブOAuth2セッション一覧表示
- セッション統計情報（総セッション数、ユニークユーザー数）
- メールアドレスによる検索
- セッション削除によるユーザーの強制ログアウト
- セッションTTL（有効期限）の監視
- 個別セッション失効

**🎫 Tokensタブ**:
- 全ユーザーのJWTトークン一覧表示
- トークン統計情報（合計、アクティブ、期限切れ、失効済み）
- メールアドレスまたはトークン名による検索
- アクティブトークンの失効
- リアルタイムステータス更新

**🧹 Cleanupタブ**（NEW）:
- **削除前のクリーンアップ対象プレビュー**
  - 孤立JWT Token ID数
  - 孤立メタデータ数
  - 推定解放容量
  - 削除対象アイテムの詳細JSON
- **手動クリーンアップ操作の実行**
  - user:tokensセットからの孤立Token ID削除
  - 孤立active_user_metadataエントリの削除
  - 空トークンセットのクリーンアップ
  - 削除件数と解放メモリを含む実行結果の表示
- **詳細監査証跡付きクリーンアップログの表示**
  - **実行ごとの展開可能な削除明細**（NEW）
  - ユーザーメールアドレスとトークンID
  - 削除理由とタイムスタンプ
  - 30日間のログ保持
  - 完全な実行履歴

### Token Manager UIでJWTトークンを生成

1. ブラウザで `http://{your-fqdn}/token-manager` を開く
2. トークン名と有効期限を入力
3. "Generate Token"をクリック
4. 生成されたJWTトークンをコピーしてAPIアクセスに使用

### API経由でJWTトークンを生成
```bash
curl -X POST http://{your-fqdn}/api/token/generate \
  -H "Cookie: _oauth2_proxy=YOUR_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "token_name": "My API Token",
    "expires_in": 2592000
  }'
```

### JWTを使用したAPI呼び出し
```bash
curl -X POST http://{your-fqdn}/v1/messages \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "こんにちは！"}]
  }'
```

### Roo Codeの設定

VS Codeの設定で以下を追加:
```json
{
  "rooCode.api.endpoint": "http://{your-fqdn}/v1",
  "rooCode.api.key": "your_jwt_token_here",
  "rooCode.model": "claude-sonnet-4-20250514"
}
```

`{your-fqdn}`は実際のドメインに置き換えてください。

---

## 🔧 設定

### サポートされているモデル

`litellm_config.yaml`でモデルを追加:
```yaml
model_list:
  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY
```

### JWTトークンの有効期限

デフォルト: 30日（2,592,000秒）
最大: 90日（7,776,000秒）

`lua/token_generator.lua`で変更:
```lua
local MAX_EXPIRES_IN = 7776000  -- 90日
```

### OAuth2セッションタイムアウト

デフォルト: 24時間

`oauth2_proxy.cfg`で変更:
```ini
cookie_expire = "24h"
```

### 管理者設定

`.env`で管理者ユーザーを設定:
```bash
# スーパー管理者（全権限）
SUPER_ADMIN_EMAIL=admin@example.com

# 通常管理者（トークン・セッション管理）
ADMIN_EMAILS=admin1@example.com,admin2@example.com
```

### クリーンアップログ保持期間

`.env`で設定:
```bash
# クリーンアップログ保持期間（日数）
CLEANUP_LOG_RETENTION_DAYS=30
```

### LiteLLM共有APIキーのセットアップ（必須）

インストール後、LiteLLMで**共有APIキー**（Virtual Key）を作成する必要があります：

#### ステップ1: LiteLLM管理UIにアクセス
```
http://{your-fqdn}:4000
```

`.env`の`LITELLM_MASTER_KEY`で設定したマスターキーでログイン

#### ステップ2: Virtual Keyを作成

1. **"Keys"**タブに移動
2. **"+ Create Key"**をクリック
3. キーを設定:
   - **Key Name**: `shared-api-key`
   - **Max Budget**: 全ユーザーの合計予算を設定
   - **Duration**: 予算リセット期間を設定（例: `30d`）
4. **"Create Key"**をクリック
5. 生成されたキーをコピー（`sk-...`で始まる）

#### ステップ3: .envを更新
```bash
# .envに追加
LITELLM_SHARED_KEY=sk-xxxxxxxxxxxxxxxx  # 生成されたvirtual key
```

#### ステップ4: サービスを再起動
```bash
sudo docker compose restart
```

**重要な注意事項**:
- ⚠️ **全ユーザーがこの単一のAPIキーを共有します**
- ⚠️ **予算制限は全ユーザーの合計使用量に適用されます**
- ⚠️ **複数の共有キーは利用できません**
- ✅ 個別のユーザー使用量はログ内のOAuth2メールアドレスで追跡されます
- ✅ ユーザー毎の予算制限も設定可能です（下記参照）

### ユーザー毎の予算制限（オプション）

LiteLLMのEnd User機能を使用して、個別のユーザー予算制限を設定できます：

**重要**: LiteLLMはユーザーが最初にAPIリクエストを行った際に、OAuth2メールアドレスを使用してCustomerレコードを自動的に作成します。その後、予算設定を更新できます。

#### 新規顧客の作成（API）

まだリクエストを行っていないユーザーの場合：
```bash
curl -X POST 'http://{your-fqdn}:4000/customer/new' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "user@example.com",
    "max_budget": 10.0,
    "budget_duration": "30d"
  }'
```

**注意**: `"Customer already exists"`というエラーが表示された場合は、既に該当ユーザーからのリクエストが存在するため、下記の更新エンドポイントを使用してください。

#### 既存顧客の予算更新（API）

既にリクエストを行ったことがあるユーザーの場合：
```bash
curl -X POST 'http://{your-fqdn}:4000/customer/update' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "sample@example.com",
    "max_budget": 10.0,
    "budget_duration": "30d"
  }'
```

#### ユーザー使用状況の確認

**LiteLLM UI経由（推奨）**:
1. LiteLLM管理UIにアクセス: `http://{your-fqdn}:4000`
2. **"Usage"** → **"Old Usage"** → **"Customer Usage"** タブに移動
3. 顧客のメールアドレス別に使用状況を確認:
   - **Customer**: メールアドレス（例: sample@example.com）
   - **Spend**: 総コスト
   - **Total Events**: リクエスト数

**注意**: UI上での予算設定はできません。予算設定は上記のAPIエンドポイントを使用してください。

**API経由**:
```bash
curl -X GET 'http://{your-fqdn}:4000/customer/info?end_user_id=user@example.com' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY'
```

**仕組み**:
- OpenRestyが各APIリクエストにOAuth2メールアドレスを自動付与
- LiteLLMが最初のリクエスト時にCustomerレコードを自動作成
- LiteLLMがメールアドレス毎に使用量を追跡
- 予算制限が自動的に適用される
- ユーザーが制限を超えるとリクエストが拒否される

**ドキュメント**: [LiteLLM End User Budgets](https://docs.litellm.ai/docs/proxy/customers)

---

## 🧹 Redisクリーンアップ機能

### 概要

Redisクリーンアップ機能は、時間とともに蓄積される孤立データを自動的に識別・削除します：

**TTLによる自動削除**:
- `token:info:*` - トークン期限切れ時に削除
- `revoked:token:*` - 元のトークン有効期限で削除
- `active_user_deleted:*` - 7日後に削除
- `_oauth2_proxy*` - セッション期限切れ時に削除

**手動クリーンアップが必要**:
- `user:tokens:*` セット内の孤立トークンID（`token:info`削除後も残る）
- 孤立した `active_user_metadata:*` エントリ

### 使用方法

1. **Cleanupタブにアクセス**:
```
   https://{your-fqdn}/token-session-manager
   → 「🧹 Cleanup」タブをクリック
```

2. **クリーンアップ対象のプレビュー**:
   - 「🔍 プレビュー（削除せず確認）」をクリック
   - 孤立トークンとメタデータの件数を表示
   - 削除対象の詳細JSON表示
   - 解放される推定メモリ量を表示

3. **クリーンアップ実行**:
   - 「🧹 クリーンアップ実行」をクリック
   - 削除を確認
   - 実行結果を表示:
     - Cleanup ID
     - 実行タイムスタンプ
     - 削除件数
     - 解放メモリ
     - ユーザーメールとトークンIDを含む詳細削除ログ

4. **クリーンアップログ表示**:
   - 「📋 ログ表示」をクリック
   - 過去のクリーンアップ実行を閲覧
   - **実行ごとの詳細削除ログを展開**（NEW）
     - 「📋 削除明細を表示」ボタンをクリック
     - ユーザーメール、トークンID、削除理由を表示
     - カラーコード化された削除タイプと理由
     - 各削除のタイムスタンプ
   - クリーンアップ履歴を追跡（30日間保持）

### Cleanup API

**クリーンアップ対象のプレビュー**:
```bash
curl -X GET https://{your-fqdn}/api/admin/redis/cleanup/preview \
  -H "Cookie: _oauth2_proxy=..."
```

**クリーンアップ実行**:
```bash
curl -X POST https://{your-fqdn}/api/admin/redis/cleanup \
  -H "Cookie: _oauth2_proxy=..."
```

**クリーンアップログ表示**:
```bash
curl -X GET https://{your-fqdn}/api/admin/redis/cleanup/logs \
  -H "Cookie: _oauth2_proxy=..."
```

---

## 🛡️ セッション管理とユーザーBAN

### 即時BAN機能（NEW）

管理者は、退職やセキュリティインシデントなどの緊急時に、ユーザーを即座にBANできます。

**動作の仕組み**:

1. **管理者がユーザーをBAN** Active Usersタブ経由
2. **全ユーザーセッションが即座に削除** Redisから
3. **BAN記録が作成される** 7日間有効期限
4. **ユーザーの次のリクエストが失敗** 401 Unauthorized
   - **OAuth2認証**: ログイン画面へリダイレクト、7日間ブロック
   - **JWT token認証**: 401エラー、BAN残り時間表示
5. **すべてのアクセス経路でBAN適用**
   - ブラウザアクセス（OAuth2）
   - API/CLIアクセス（JWT token）
   - Roo Code VS Code extension（JWT token）
6. **7日後に自動BAN解除** + 再認証で利用再開

**BAN期間**: 7日間（604,800秒）

**対応アクセス方法**:
- ✅ OAuth2ブラウザアクセス
- ✅ JWT token API呼び出し
- ✅ Roo Code / VS Code extension
- ✅ CLI tools

**使用方法**:

**方法1: Token & Session Manager UI（推奨）**

1. `http://{your-fqdn}/token-session-manager` にアクセス（管理者のみ）
2. **Active Users** タブをクリック
3. メールアドレスでユーザーを検索
4. **🔥 即時BAN (7日間)** ボタンをクリック
5. ダイアログでBANを確認

**期待されるUI動作**:
- 成功メッセージ: "✅ {email} を即時BANしました(7日間)"
- 削除されたセッション数が表示される
- Active Usersリストが自動的に更新される
- ユーザー行が赤色でハイライトされBANステータスバッジが表示

**方法2: API経由でBAN**
```bash
curl -X POST http://{your-fqdn}/api/admin/sessions/revoke-user \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com"
  }'
```

**期待されるレスポンス**:
```json
{
  "message": "User banned successfully",
  "user_email": "user@example.com",
  "deleted_count": 2,
  "ban_duration_seconds": 604800,
  "deleted_by": "admin@example.com"
}
```

**BANされたユーザーがJWT tokenでアクセスした場合**:
```bash
# リクエスト
curl -X POST http://{your-fqdn}/v1/messages \
  -H "Authorization: Bearer BANNED_USER_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4","max_tokens":100,"messages":[...]}'

# レスポンス
HTTP/1.1 401 Unauthorized
{
  "error": {
    "type": "authentication_error",
    "message": "User is banned for 6 days 23 hours"
  }
}
```

**ユーザーのBAN解除**:
```bash
curl -X DELETE http://{your-fqdn}/api/admin/sessions/unban/{email} \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

### 強制ログアウト機能

管理者はユーザーのセッションを強制的に削除して、即座にアクセスを無効化できます。

#### 動作の仕組み

1. **管理者がセッションを削除** Sessionsタブまたはapi経由
2. **セッションがRedisから即座に削除される**
3. **ユーザーの次のリクエストが401 Unauthorizedで失敗**
4. **ユーザーが自動的にログイン画面にリダイレクトされる**
5. **ユーザーはアクセスを回復するために再認証が必要**

#### 使用方法

**方法1: Token & Session Manager UI（推奨）**

1. `http://{your-fqdn}/token-session-manager` にアクセス（管理者のみ）
2. **Sessions** タブをクリック
3. メールアドレスでユーザーを検索
4. ユーザーのセッションの横にある **削除** ボタンをクリック
5. ダイアログで削除を確認

**期待されるUI動作**:
- 成功メッセージが表示される: "Session を削除しました"
- セッションリストが自動的に更新される
- 削除されたセッションはリストに表示されなくなる

**方法2: 単一セッションの削除（API）**
```bash
# UIまたはAPIからセッションキーを取得してから削除
curl -X DELETE http://{your-fqdn}/api/admin/sessions/{SESSION_KEY} \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

**期待されるレスポンス**:
```json
{
  "message": "Session deleted successfully",
  "session_key": "_oauth2_proxy-abc123...",
  "deleted_by": "admin@example.com"
}
```

#### 技術詳細

**実装**:
- **session_admin.lua**: 全てのセッション管理APIエンドポイントを処理
- **auth_handler.lua**: JWT token認証時にBAN状態をチェック
- **active_user_tracker.lua**: OAuth2認証時にBAN状態をチェック
- **OAuth2 Proxy**: セッションをRedisに `_oauth2_proxy-*` のキーパターンで保存
- **セッションデータ**: ユーザーメールアドレス、作成時刻、有効期限、認証メタデータを含む

**検索されるセッションキーパターン**:
```
_oauth2_proxy-*      # プライマリパターン（ハイフン形式）
_oauth2_proxy_*      # 代替パターン（アンダースコア形式）
_oauth2_proxy:*      # 代替パターン（コロン形式）
oauth2-*             # レガシーパターン
oauth2_*             # レガシーパターン
session:*            # 汎用パターン
```

**動作**:
- ✅ Redisからの即時セッション削除
- ✅ 次のリクエストでユーザーが自動的にログアウト
- ✅ ユーザーごとの複数セッションをサポート
- ✅ 管理者監査ログを含む
- ✅ 他のユーザーのセッションに影響なし
- ✅ OAuth2とJWT token両方のBAN状態チェック

**ユーザー体験**:
```
【OAuth2ユーザーの場合】
管理者がセッション削除/BAN実行
  ↓
ユーザーがブラウジングを続ける
  ↓
保護されたエンドポイントへの次のリクエスト
  ↓
401 Unauthorized: Cookieが見つからないか無効
  ↓
Auth0ログイン画面への自動リダイレクト
  ↓
BAN中の場合: 7日間ログイン不可
BAN解除後: 再ログインで利用再開

【JWT tokenユーザーの場合】
管理者がBAN実行
  ↓
ユーザーがAPI/CLI/Roo Codeからアクセス
  ↓
JWT token検証 + BAN状態チェック
  ↓
401 Unauthorized: "User is banned for X days Y hours"
  ↓
BAN解除後: 既存のJWT tokenで即座に利用再開
```

---

## 📊 監視

### Langfuseダッシュボード

トレーシングと分析にアクセス:
```
http://{your-fqdn}:3000
```

**利用可能なメトリクス**:
- ユーザー/モデル別リクエスト数
- トークン使用量とコスト
- エラー率
- レスポンス時間

### ログの確認
```bash
# 全サービス
sudo docker compose logs -f

# 特定サービス
sudo docker compose logs -f litellm
sudo docker compose logs -f openresty
```

---

## 🛠️ 管理

### トークン管理API

| エンドポイント | メソッド | 説明 |
|--------------|---------|------|
| `/api/token/generate` | POST | 新しいJWTトークンを生成 |
| `/api/token/list` | GET | ユーザーのトークン一覧 |
| `/api/token/info?token_id=xxx` | GET | トークン詳細取得 |
| `/api/token/revoke` | POST | トークンを失効 |

### 管理者トークン・セッション管理API

| エンドポイント | メソッド | 説明 | 認証要件 |
|--------------|---------|------|----------|
| `/api/admin/tokens` | GET | 全ユーザーのトークン一覧を取得 | 管理者のみ |
| `/api/admin/tokens/{token_id}` | DELETE | 任意のユーザーのトークン失効 | 管理者のみ |
| `/api/admin/sessions` | GET | 全アクティブセッション一覧を取得 | 管理者のみ |
| `/api/admin/sessions/{session_key}` | DELETE | 特定のセッションを削除 | 管理者のみ |
| `/api/admin/sessions/active-users` | GET | アクティブユーザー一覧を取得 | 管理者のみ |
| `/api/admin/sessions/revoke-user` | POST | ユーザーBAN - 全セッション失効 | 管理者のみ |
| `/api/admin/sessions/unban/{email}` | DELETE | ユーザーBAN解除 | 管理者のみ |
| `/api/admin/sessions/stats` | GET | セッション統計を取得 | 管理者のみ |
| `/api/admin/redis/cleanup/preview` | GET | クリーンアップ対象プレビュー | 管理者のみ |
| `/api/admin/redis/cleanup` | POST | クリーンアップ実行 | 管理者のみ |
| `/api/admin/redis/cleanup/logs` | GET | クリーンアップログ表示 | 管理者のみ |

### ユーザー管理

1. **ユーザー追加**: Auth0ダッシュボードで追加
2. **ユーザー削除**: Auth0から削除 → 全トークンが24時間以内に無効化
3. **緊急BAN**: Active Usersタブの即時BAN機能を使用（即座、7日間ブロック、全アクセス経路に適用）
4. **強制ログアウト**: Sessionsタブ経由でセッション削除機能を使用（即座に有効）

---

## 🔒 セキュリティ

### ベストプラクティス

- ✅ JWTトークンを安全に保管（環境変数またはパスワードマネージャー）
- ✅ トークンを定期的にローテーション
- ✅ 本番環境ではHTTPSを使用
- ✅ `.env`ファイルのパーミッション設定: `chmod 600 .env`
- ✅ Auth0でMFAを有効化
- ✅ Langfuseで不審な活動を監視
- ✅ 緊急時の脅威対応には即時BAN機能を使用
- ✅ 即座のユーザーロックアウトにはセッション削除機能を使用
- ✅ クリーンアップログを定期的に確認し、異常を検出
- ✅ Token & Session Manager経由でアクティブセッションを定期的に監査

### OAuth2セッション検証とBAN機能

**現在の実装**:
- **OAuth2認証**:
  - セッション検証が全リクエストで実行
  - BAN状態チェック（`active_user_deleted:*`）
  - BANされたユーザーは7日間ログイン不可
- **JWT token認証**:
  - JWT検証が全APIリクエストで実行
  - BAN状態チェック（`active_user_deleted:*`）
  - BANされたユーザーは401 Unauthorizedを返す
- **統合管理**:
  - OAuth2のメールアドレスが全LiteLLM APIリクエストに付与
  - OAuth2とJWT token両方のユーザーがActive Usersタブに表示
  - 認証方法（OAuth2/JWT）の記録
  - ユーザー毎の追跡が可能
- **トークン失効**: Redisブラックリスト経由で即座に有効化
- **強制ログアウト機能**: セッション削除による即座のアクセス無効化
- **即時BAN機能**: 全アクセス経路で7日間ブロック
- **リアルタイムセッション監視**: Active User追跡

**実装予定の強化機能**:
- OAuth2セッションが存在し有効である必要があります
- セッションは24時間ごとに失効します
- OAuth2未認証者は24時間後にアクセス不可となります
- JWTトークンの自動更新機能（実装予定）

---

## 📚 ドキュメント

| ドキュメント | 説明 |
|------------|------|
| [QUICKSTART.md](docs/QUICKSTART.md) | 5分セットアップガイド |
| [SETUP_DETAILED.md](docs/SETUP_DETAILED.md) | 詳細インストール手順 |
| [API_USAGE.md](docs/API_USAGE.md) | APIリファレンス |
| [OAUTH2_SESSION_CHECK_GUIDE.md](docs/OAUTH2_SESSION_CHECK_GUIDE.md) | セッション検証機能 |
| [OPERATIONS.md](docs/OPERATIONS.md) | 日常運用ガイド |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | よくある問題 |
| [CHANGELOG.md](CHANGELOG.md) | バージョン履歴 |

---

## 🐛 トラブルシューティング

### よくある問題

| 問題 | 解決方法 |
|------|---------|
| 認証ループ | Auth0のコールバックURL設定を確認 |
| JWT検証失敗 | lua-resty-jwtを再インストール |
| OAuth2セッション期限切れ | ブラウザで再認証 |
| 接続拒否 | コンテナの状態を確認: `docker compose ps` |
| セッション削除が機能しない | Redis接続とセッションキー形式を確認 |
| UIでセッションが表示されない | 管理者ユーザーでログインしていることを確認 |
| クリーンアップ動作せず | 管理者権限とRedis接続を確認 |
| BANが効かない | メールアドレスの一致とBAN record作成を確認 |
| JWT tokenユーザーがBAN されない | auth_handler.luaのBAN状態チェック実装を確認 |
| 削除明細を展開できない | token_session_manager v4.0+を使用していることを確認 |

### デバッグモード

`nginx.conf`で詳細ログを有効化:
```nginx
error_log /var/log/nginx/error.log debug;
```

---

## 🤝 コントリビューション

プルリクエストを歓迎します！

1. リポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

---

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。詳細は[LICENSE](LICENSE)ファイルを参照してください。

---

## 🙏 謝辞

- [LiteLLM](https://github.com/BerriAI/litellm) - LLMプロキシ
- [OAuth2 Proxy](https://github.com/oauth2-proxy/oauth2-proxy) - OAuth2認証
- [OpenResty](https://openresty.org/) - 高性能Webプラットフォーム
- [Langfuse](https://langfuse.com/) - LLM可観測性
- [Auth0](https://auth0.com/) - アイデンティティプラットフォーム
- [Claude](https://www.anthropic.com/claude) (Anthropic) - ドキュメント作成と開発支援のためのAIアシスタント

---

## 📞 サポート

- 📖 ドキュメント: `docs/`ディレクトリを確認
- 🐛 Issue: [GitHub Issues](https://github.com/nakacya/llm-gateway-oauth/issues)
- 💬 ディスカッション: [GitHub Discussions](https://github.com/nakacya/llm-gateway-oauth/discussions)

---

**安全なチームLLMコラボレーションのために ❤️ で構築**
