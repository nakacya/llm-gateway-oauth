# Changelog

All notable changes to the LiteLLM Gateway OAuth2 project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [11.2] - 2025-11-10

### 🗑️ Removed

- **Port 80の `/api/token/` エンドポイント**
  - OAuth2 Proxyにプロキシされていたが機能していなかった
  - アクセスログで使用されていないことを確認（0件）
  - 実際のトークン管理はPort 8080で正常動作中
  - 正味8行削減（658行 → 650行）

### ✅ Verified

- Phase 1-7 検証完了
  - 基本動作、OAuth2認証、ユーザー追跡
  - トークン管理、LLM API、Session/BAN機能
  - パフォーマンス（平均0.912ms、標準偏差0.24ms）
- 3つの管理画面システムの正常動作確認
  - `token-manager` (一般ユーザー向け)
  - `token-session-manager` (管理者向け)
  - `admin-manager` (スーパー管理者向け)

### 📚 Documentation

- `CHANGELOG_v11.2_20251110.md` - 詳細な変更履歴
- `NGINX_UNUSED_ENDPOINTS_ANALYSIS_20251110.md` - 未使用エンドポイント分析レポート
- `NGINX_V11.1_VERIFICATION_REPORT_20251110.md` - Phase 1-7 検証結果レポート

---

## [11.1] - 2025-11-08

### 🔧 Changed

- **ログレベル最適化**: `debug` → `info`（本番環境向け）
- **アクティブユーザー追跡の関数化**: 5箇所の重複コードを `_G.track_user()` 関数に統合
- **upstream最適化**: keepalive設定追加（keepalive_requests, keepalive_timeout）

### 📊 Improved

- コード行数削減: 約55行
- 可読性・保守性の向上
- context付きログでトラッキング箇所の識別が容易に

### 🐛 Fixed

- デバッグコード保持（`#X#` コメント）

---

## [11.0] - 2025-11-08

### 🎉 Added

- **即時BAN機能**: ユーザーの即時アクセス停止が可能に
  - 7日間のBAN期間設定
  - 再認証時の自動ブロック
  - BAN解除機能

### 🔧 Changed

- **統合管理画面**: token-session-manager の実装
  - トークン管理
  - セッション管理
  - アクティブユーザー一覧

### 📚 Documentation

- `NGINX_V11.1_VERIFICATION_PLAN.md` - 検証計画書

---

## [10.30] - 2025-10-30

### 🎉 Added

- **OAuth2認証システム**: Auth0統合
- **LiteLLM Gateway**: 複数LLMプロバイダーへの統合アクセス
- **トークン管理システム**: JWT-based認証
- **管理者管理**: 3層の権限システム
  - スーパー管理者
  - 一般管理者
  - 一般ユーザー

### 🔧 Infrastructure

- OpenResty/nginx + Lua
- OAuth2 Proxy
- Redis (セッション/トークンストレージ)
- PostgreSQL (ユーザー管理)
- Langfuse (トレーシング)
- ClickHouse (アナリティクス)

---

## Release Notes

### v11.2 (2025-11-10)

**Focus**: コードクリーンアップとエンドポイント整理

**Key Changes**:
- 未使用エンドポイントの削除
- 全Phase（1-7）検証完了
- パフォーマンス確認（平均0.912ms）

**Migration**: 影響なし（未使用エンドポイントの削除のみ）

**Breaking Changes**: なし

---

### v11.1 (2025-11-08)

**Focus**: コード整理とパフォーマンス最適化

**Key Changes**:
- アクティブユーザー追跡の関数化
- upstream接続最適化
- ログレベル調整

**Migration**: 影響なし（後方互換性あり）

**Breaking Changes**: なし

---

### v11.0 (2025-11-08)

**Focus**: セキュリティ強化

**Key Changes**:
- 即時BAN機能実装
- 統合管理画面（token-session-manager）
- セッション管理強化

**Migration**: 管理画面のURLが追加されました
- 新規: `/token-session-manager` (統合管理画面)
- 既存: `/token-manager` (一般ユーザー向け)
- 既存: `/admin-manager` (スーパー管理者向け)

**Breaking Changes**: なし

---

### v10.30 (2025-10-30)

**Focus**: 初期リリース

**Key Changes**:
- OAuth2認証システム
- LiteLLM Gateway統合
- 基本的な管理機能

---

## Contributing

詳細な開発ガイドは [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## Support

問題が発生した場合:
1. [Issues](https://github.com/nakacya/llm-gateway-oauth/issues) で既存の問題を検索
2. 新しい問題を作成する際は、以下を含めてください:
   - nginx.confのバージョン
   - エラーログ
   - 再現手順

## Links

- **Documentation**: [README.md](README.md)
- **Architecture**: [OVERVIEW_md_-_完成した構成の概要.md](OVERVIEW_md_-_完成した構成の概要.md)
- **Setup Guide**: [README_md_-_セットアップと使用方法.md](README_md_-_セットアップと使用方法.md)
