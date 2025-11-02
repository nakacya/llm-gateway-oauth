#!/bin/bash

# セットアップスクリプト（sudo環境対応）
set -e

echo "======================================"
echo "LiteLLM OAuth + Token Setup"
echo "======================================"

# カラー定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 環境変数ファイルの存在確認
if [ ! -f .env ]; then
    echo -e "${YELLOW}[INFO] .envファイルが見つかりません。.env.exampleからコピーします...${NC}"
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}[OK] .envファイルを作成しました${NC}"
    else
        echo -e "${RED}[ERROR] .env.exampleが見つかりません${NC}"
        exit 1
    fi
fi

# JWT_SECRETが設定されているかチェック
if grep -q "JWT_SECRET=your-jwt-secret" .env || grep -q "JWT_SECRET=$" .env; then
    echo -e "${YELLOW}[INFO] JWT_SECRETを生成します...${NC}"
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
    if [ "$(uname)" == "Darwin" ]; then
        # macOS
        sed -i '' "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
    else
        # Linux
        sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
    fi
    echo -e "${GREEN}[OK] JWT_SECRETを生成しました${NC}"
fi

# 必要なディレクトリ作成
echo -e "${YELLOW}[INFO] ディレクトリ構造を作成中...${NC}"
mkdir -p lua
mkdir -p scripts
mkdir -p docs
mkdir -p openresty/html

# token_manager.htmlを配置
if [ -f token_manager.html ]; then
    cp token_manager.html openresty/html/
    echo -e "${GREEN}[OK] token_manager.htmlを配置しました${NC}"
fi

# Dockerコンテナ起動
echo -e "${YELLOW}[INFO] Dockerコンテナを起動中...${NC}"
sudo docker compose up -d --remove-orphans

# コンテナの起動を待機（時間を延長）
echo -e "${YELLOW}[INFO] サービスの起動を待機中（5秒）...${NC}"
sleep 5

# OpenRestyの状態確認
echo -e "${YELLOW}[INFO] OpenRestyの状態を確認中...${NC}"
for i in {1..10}; do
    if sudo docker ps | grep openresty | grep -q "Up"; then
        echo -e "${GREEN}[OK] OpenRestyが起動しました${NC}"
        break
    fi
    echo -e "${YELLOW}[INFO] 起動待機中... ($i/10)${NC}"
    sleep 3
done

# OpenRestyが再起動ループしていないか確認
if sudo docker ps | grep openresty | grep -q "Restarting"; then
    echo -e "${RED}[ERROR] OpenRestyが再起動ループしています${NC}"
    echo -e "${YELLOW}[INFO] ログを確認してください: sudo docker logs openresty${NC}"
    sudo docker logs openresty | tail -20
    exit 1
fi

# ログディレクトリの作成
echo -e "${YELLOW}[INFO] ログディレクトリを作成中...${NC}"
sudo docker exec openresty sh -c "mkdir -p /var/log/nginx && \
    chmod 755 /var/log/nginx" || true

# OpenRestyにlua-resty-jwtをインストール
echo -e "${YELLOW}[INFO] OpenRestyにlua-resty-jwtをインストール中...${NC}"
sudo docker exec openresty sh -c "apk add --no-cache git && \
    cd /tmp && \
    rm -rf /tmp/lua-resty-jwt && \
    git clone https://github.com/SkyLothar/lua-resty-jwt.git && \
    cd lua-resty-jwt && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/" || true

# OpenRestyにlua-resty-hmacをインストール
echo -e "${YELLOW}[INFO] OpenRestyにlua-resty-hmacをインストール中...${NC}"
sudo docker exec openresty sh -c "apk add --no-cache git && \
    cd /tmp && \
    rm -rf /tmp/lua-resty-hmac && \
    git clone https://github.com/jkeys089/lua-resty-hmac.git && \
    cd /tmp/lua-resty-hmac && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/" || true

# OpenRestyにlua-resty-stringをインストール（依存関係）
echo -e "${YELLOW}[INFO] OpenRestyにlua-resty-stringをインストール中...${NC}"
sudo docker exec openresty sh -c "apk add --no-cache git && \
    cd /tmp && \
    rm -rf /tmp/lua-resty-string && \
    git clone https://github.com/openresty/lua-resty-string.git && \
    cd lua-resty-string && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/" || true

# htmlディレクトリの権限設定
echo -e "${YELLOW}[INFO] htmlディレクトリの権限を設定中...${NC}"
sudo docker exec openresty sh -c "mkdir -p /usr/local/openresty/nginx/html && \
    chmod 755 /usr/local/openresty/nginx/html" || true


# 設定の再読み込み
echo -e "${YELLOW}[INFO] OpenRestyの設定を再読み込み中...${NC}"
sudo docker exec openresty openresty -t
if [ $? -eq 0 ]; then
    sudo docker exec openresty openresty -s reload
    echo -e "${GREEN}[OK] 設定を再読み込みしました${NC}"
else
    echo -e "${RED}[ERROR] 設定ファイルにエラーがあります${NC}"
    exit 1
fi

# ヘルスチェック
echo ""
echo "======================================"
echo "ヘルスチェック"
echo "======================================"

check_service() {
    local name=$1
    local url=$2
    
    sleep 2
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
        echo -e "${GREEN}[OK] $name: 起動中${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] $name: 起動失敗または未準備${NC}"
        return 1
    fi
}

check_service "OpenResty" "http://localhost:8080/health"
check_service "LiteLLM" "http://localhost:4000/health"

# OAuth2 Proxyは認証が必要なので、プロセス確認のみ
if sudo docker compose ps | grep oauth2-proxy | grep -q "Up"; then
    echo -e "${GREEN}[OK] OAuth2 Proxy: 起動中${NC}"
else
    echo -e "${RED}[ERROR] OAuth2 Proxy: 起動失敗${NC}"
fi

# Langfuseは起動に時間がかかるので、コンテナ状態のみ確認
if sudo docker compose ps | grep langfuse | grep -q "Up"; then
    echo -e "${GREEN}[OK] Langfuse: 起動中${NC}"
else
    echo -e "${YELLOW}[WARN] Langfuse: 起動中または未準備${NC}"
fi

echo ""
echo "======================================"
echo "セットアップ完了"
echo "======================================"
echo ""
echo -e "${GREEN}以下のURLでサービスにアクセスできます:${NC}"
echo ""
echo "  OAuth Login:        http://litellm.nakacya.jp/"
echo "  Token Manager:      http://litellm.nakacya.jp/token-manager"
echo "  API Endpoint:       http://litellm.nakacya.jp/v1"
echo "  Langfuse UI:        http://localhost:3000"
echo ""
echo -e "${YELLOW}次のステップ:${NC}"
echo ""
echo "  1. ブラウザで http://litellm.nakacya.jp/ にアクセス"
echo "  2. Auth0でログイン（nakacya@gmail.com）"
echo "  3. http://litellm.nakacya.jp/token-manager にアクセス"
echo "  4. 'トークンを生成' ボタンをクリック"
echo "  5. 発行されたトークンをRoo Codeに設定"
echo ""
echo -e "${YELLOW}Roo Code設定:${NC}"
echo "  API Endpoint: http://litellm.nakacya.jp/v1"
echo "  API Key:      <発行したトークン>"
echo "  Model:        claude-sonnet-4-20250514"
echo ""
echo -e "${YELLOW}トラブルシューティング:${NC}"
echo "  ログ確認:     sudo docker compose logs -f"
echo "  再起動:       sudo docker compose restart"
echo "  完全再構築:   sudo docker compose down && sudo docker compose up -d"
echo ""
echo "======================================"
