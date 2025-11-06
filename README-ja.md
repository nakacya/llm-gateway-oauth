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
  - **再ログイン防止機能付きセッション削除**（NEW）
  - OAuth2セッションチェック（実装予定：毎日再認証）

- **📊 完全な可観測性**
  - Langfuseによるリアルタイムトレーシング
  - ユーザー別使用状況分析（全APIリクエストにOAuth2メールアドレスを付与）
  - モデル/ユーザー別コスト追跡
  - ユーザー個別の予算制限設定が可能

- **🔄 トークン・セッション管理**
  - Webベースのトークン管理UI
  - **Webベースのセッション管理UI**（NEW）
  - ユーザーごとに複数トークン発行可能
  - カスタム有効期限設定
  - **削除フラグシステムによる強制ログアウト**（NEW）

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
│  - JWT検証                           │
│  - OAuth2セッションチェック           │
│  - セッション削除フラグチェック (NEW) │
│  - リクエストルーティング             │
└──────┬───────────┬───────────────────┘
       │           │
       │           └──────────┐
       │                      ↓
       │                ┌──────────┐
       │                │  Redis   │
       │                │(トークン  │
       │                │ セッション│
       │                │ フラグ)  │
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
3. `http://{your-fqdn}/token-manager` でトークンマネージャーにアクセス
4. Web UIからJWTトークンを生成・管理

**利用可能なUI**:
- **Token Manager** (`/token-manager`): APIトークンの生成と管理
- **Token & Session Manager** (`/token-session-manager`): トークンとセッションの統合管理（管理者のみ）
- **Admin Manager** (`/admin-manager`): ユーザー管理用の管理パネル（管理者のみ）

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
- LiteLLMがメールアドレス毎に使用量を追跡
- 予算制限が自動的に適用される
- ユーザーが制限を超えるとリクエストが拒否される

**ドキュメント**: [LiteLLM End User Budgets](https://docs.litellm.ai/docs/proxy/customers)

---

## 🛡️ セッション管理（NEW）

### 強制ログアウト機能

管理者は削除フラグシステムを使用して、ユーザーのセッションを強制的に削除し、自動再ログインを防止できます。

#### 動作の仕組み

1. **管理者がセッションを削除** Token & Session ManagerまたはAPI経由
2. **削除フラグが作成される** Redisに60秒間有効なフラグを作成
3. **ユーザーがアクセスを試みる**（60秒以内）
4. **システムが削除フラグをチェック** セッション再作成をブロック
5. **401エラーを返す** メッセージ: "セッションが削除されました"
6. **ログイン画面にリダイレクト**
7. **60秒後**、削除フラグが自動的に期限切れ
8. **再ログイン可能** 通常通りログインできる

#### 使用方法

**方法1: Token & Session Manager UI（推奨）**

1. `http://{your-fqdn}/token-session-manager` にアクセス（管理者のみ）
2. **Sessions** タブに移動
3. メールアドレスでユーザーを検索
4. ユーザーのセッションの横にある **Delete** ボタンをクリック
5. 削除を確認

**期待されるレスポンス**:
```json
{
  "message": "User sessions deleted successfully",
  "user_email": "user@example.com",
  "deleted_count": 1,
  "deletion_flag_created": true,
  "deletion_flag_ttl": 60
}
```

**方法2: API**

```bash
# 内部ポート経由（OAuth2をバイパス）
curl -X POST http://localhost:8080/api/admin/sessions/revoke-user \
  -H "Content-Type: application/json" \
  -H "X-Forwarded-Email: admin@example.com" \
  -d '{"user_email":"user@example.com"}'
```

#### 技術詳細

**実装**:
- **session_admin.lua**: セッション削除時に削除フラグを作成
- **active_user_tracker.lua**: active_user作成前に削除フラグをチェック
- **削除フラグTTL**: 60秒（自動期限切れ）

**動作**:
- ✅ セッション削除後の自動再ログインを防止
- ✅ ユーザーに明確なエラーメッセージを表示
- ✅ 60秒後に自動期限切れで通常の再ログインが可能
- ✅ 他のユーザーへの影響なし

**ユーザー体験**:
```
管理者がセッションを削除
  ↓
ユーザーがページをリロード（60秒以内）
  ↓
401エラー: "セッションが管理者によって削除されました。再度ログインしてください。"
  ↓
ログイン画面にリダイレクト
  ↓
60秒後: 通常のログインが可能
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

### セッション管理API（NEW）

| エンドポイント | メソッド | 説明 |
|--------------|---------|------|
| `/api/admin/sessions` | GET | 全セッション一覧（管理者のみ） |
| `/api/admin/sessions/revoke-user` | POST | ユーザーセッション削除（管理者のみ） |
| `/api/admin/sessions/stats` | GET | セッション統計取得（管理者のみ） |

### ユーザー管理

1. **ユーザー追加**: Auth0ダッシュボードで追加
2. **ユーザー削除**: Auth0から削除 → 全トークンが24時間以内に無効化
3. **強制ログアウト**: セッション削除機能を使用（即座に有効）

---

## 🔒 セキュリティ

### ベストプラクティス

- ✅ JWTトークンを安全に保管（環境変数またはパスワードマネージャー）
- ✅ トークンを定期的にローテーション
- ✅ 本番環境ではHTTPSを使用
- ✅ `.env`ファイルのパーミッション設定: `chmod 600 .env`
- ✅ Auth0でMFAを有効化
- ✅ Langfuseで不審な活動を監視
- ✅ 即座のユーザーロックアウトにはセッション削除機能を使用

### OAuth2セッション検証

**現在の実装**:
- JWTトークンは全APIリクエストで検証されます
- トークン失効はRedisブラックリスト経由で即座に有効化
- OAuth2のメールアドレスが全LiteLLM APIリクエストに付与され、ユーザー毎の追跡が可能
- **再ログイン防止機能付きセッション削除**（NEW）

**実装予定の強化機能**:
- OAuth2セッションが存在し有効である必要があります
- セッションは24時間ごとに失効します
- OAuth2 未認証者は24時間後にアクセス不可となります
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

---

## 🐛 トラブルシューティング

### よくある問題

| 問題 | 解決方法 |
|------|---------|
| 認証ループ | Auth0のコールバックURL設定を確認 |
| JWT検証失敗 | lua-resty-jwtを再インストール |
| OAuth2セッション期限切れ | ブラウザで再認証 |
| 接続拒否 | コンテナの状態を確認: `docker compose ps` |
| セッション削除が機能しない | Redisで削除フラグを確認: `redis-cli GET "active_user_deleted:email"` |

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
