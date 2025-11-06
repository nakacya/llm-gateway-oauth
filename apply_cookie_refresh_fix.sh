#!/bin/bash
# apply_cookie_refresh_fix.sh - cookie_refresh無効化の自動適用スクリプト

set -e

echo "=========================================="
echo "🚀 cookie_refresh無効化 適用スクリプト"
echo "=========================================="
echo ""

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: ファイルの確認
echo "Step 1: oauth2_proxy.cfg の確認"
if [ ! -f ~/oauth2/oauth2_proxy.cfg ]; then
    echo -e "${RED}❌ ~/oauth2/oauth2_proxy.cfg が見つかりません${NC}"
    echo ""
    echo "以下の手順を実行してください:"
    echo "  1. oauth2_proxy.cfg をダウンロード"
    echo "  2. ~/oauth2/ に配置"
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ oauth2_proxy.cfg が見つかりました${NC}"
echo ""

# Step 2: バックアップ
echo "Step 2: 現在の設定をバックアップ"
BACKUP_FILE=~/oauth2/oauth2_proxy.cfg.backup.$(date +%Y%m%d_%H%M%S)
cp ~/oauth2/oauth2_proxy.cfg "$BACKUP_FILE"
echo -e "${GREEN}✅ バックアップ完了: $BACKUP_FILE${NC}"
echo ""

# Step 3: 設定ファイルをコピー
echo "Step 3: 新しい設定ファイルを適用"
sudo docker compose cp ~/oauth2/oauth2_proxy.cfg \
  oauth2-proxy:/etc/oauth2-proxy/oauth2_proxy.cfg
echo -e "${GREEN}✅ 設定ファイルをコピーしました${NC}"
echo ""

# Step 4: OAuth2 Proxyを再起動
echo "Step 4: OAuth2 Proxyを再起動"
sudo docker compose restart oauth2-proxy > /dev/null 2>&1
echo -e "${GREEN}✅ OAuth2 Proxyを再起動しました${NC}"
echo ""
echo "起動を待っています..."
sleep 5
echo ""

# Step 5: 設定の確認
echo "Step 5: 設定が正しく適用されたか確認"
echo ""
echo "OAuth2 Proxyのログ（最新10行）:"
echo "=========================================="
sudo docker compose logs oauth2-proxy | tail -10
echo "=========================================="
echo ""

# cookie_refreshの値を確認
if sudo docker compose logs oauth2-proxy | grep -q "refresh:after 0"; then
    echo -e "${GREEN}✅ cookie_refresh = 0 が正しく適用されました${NC}"
else
    echo -e "${YELLOW}⚠️  cookie_refreshの設定を確認できませんでした${NC}"
    echo "手動で確認してください:"
    echo "  sudo docker compose logs oauth2-proxy | grep 'refresh:after'"
fi
echo ""

# Step 6: コンテナの状態確認
echo "Step 6: コンテナの状態"
sudo docker compose ps oauth2-proxy
echo ""

echo "=========================================="
echo -e "${GREEN}✅ 適用完了${NC}"
echo "=========================================="
echo ""
echo "次のステップ:"
echo "  1. ブラウザでログイン"
echo "  2. 別のブラウザで別ユーザーとしてログイン"
echo "  3. 管理画面で2番目のユーザーのセッションを削除"
echo "  4. 2番目のブラウザをリロード"
echo ""
echo "期待される動作:"
echo "  ✅ ログイン画面にリダイレクトされる"
echo "  ✅ 自動再ログインされない"
echo ""
echo "テストスクリプト:"
echo "  ~/oauth2/test_hoge_logout.sh"
echo ""
