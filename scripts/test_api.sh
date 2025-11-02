#!/bin/bash

# APIテストスクリプト
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_URL="http://localhost:8080"

echo "======================================"
echo "LiteLLM API Test Script"
echo "======================================"
echo ""

# トークンの引数チェック
if [ -z "$1" ]; then
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  $0 <Bearer-Token>"
    echo ""
    echo "トークンを取得するには、まずブラウザでOAuth認証を行い、"
    echo "その後 /api/token/generate エンドポイントを呼び出してください。"
    echo ""
    echo "例:"
    echo "  # ブラウザで http://litellm.nakacya.jp にアクセスしてログイン"
    echo "  # その後、認証Cookieを使ってトークンを生成"
    echo "  curl -X POST http://localhost:8080/api/token/generate \\"
    echo "    --cookie '_oauth2_proxy=...' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"token_name\": \"Test Token\", \"expires_in\": 86400}'"
    echo ""
    exit 1
fi

TOKEN="$1"

echo -e "${YELLOW}[TEST 1] ヘルスチェック${NC}"
HEALTH_RESPONSE=$(curl -s "$BASE_URL/health")
if [ "$HEALTH_RESPONSE" == "OK" ]; then
    echo -e "${GREEN}✓ ヘルスチェック成功${NC}"
else
    echo -e "${RED}✗ ヘルスチェック失敗${NC}"
fi
echo ""

echo -e "${YELLOW}[TEST 2] JWT認証テスト（トークンなし）${NC}"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/v1/models")
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
if [ "$HTTP_CODE" == "401" ]; then
    echo -e "${GREEN}✓ 認証が正しく要求されました${NC}"
else
    echo -e "${RED}✗ 予期しないレスポンス: $HTTP_CODE${NC}"
fi
echo ""

echo -e "${YELLOW}[TEST 3] JWT認証テスト（トークンあり）${NC}"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE_URL/v1/models")
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✓ JWT認証成功${NC}"
    echo "レスポンス: $(echo "$BODY" | jq -r '.data[0].id' 2>/dev/null || echo "$BODY")"
else
    echo -e "${RED}✗ 認証失敗: $HTTP_CODE${NC}"
    echo "レスポンス: $BODY"
fi
echo ""

echo -e "${YELLOW}[TEST 4] Claude API呼び出しテスト${NC}"
CHAT_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 100,
        "messages": [
            {
                "role": "user",
                "content": "こんにちは。簡単に自己紹介してください。"
            }
        ]
    }' \
    "$BASE_URL/v1/messages")

HTTP_CODE=$(echo "$CHAT_RESPONSE" | tail -n 1)
BODY=$(echo "$CHAT_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✓ Claude API呼び出し成功${NC}"
    CONTENT=$(echo "$BODY" | jq -r '.content[0].text' 2>/dev/null)
    if [ ! -z "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
        echo "応答: $CONTENT"
    else
        echo "応答: $(echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY")"
    fi
else
    echo -e "${RED}✗ API呼び出し失敗: $HTTP_CODE${NC}"
    echo "エラー: $BODY"
fi
echo ""

echo -e "${YELLOW}[TEST 5] Chat Completions API（OpenAI互換）${NC}"
COMPLETION_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "claude-haiku-4-5-20251001",
        "messages": [
            {
                "role": "user",
                "content": "1+1は？"
            }
        ],
        "max_tokens": 50
    }' \
    "$BASE_URL/v1/chat/completions")

HTTP_CODE=$(echo "$COMPLETION_RESPONSE" | tail -n 1)
BODY=$(echo "$COMPLETION_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✓ Chat Completions API成功${NC}"
    MESSAGE=$(echo "$BODY" | jq -r '.choices[0].message.content' 2>/dev/null)
    if [ ! -z "$MESSAGE" ] && [ "$MESSAGE" != "null" ]; then
        echo "応答: $MESSAGE"
    else
        echo "応答: $(echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY")"
    fi
else
    echo -e "${RED}✗ API呼び出し失敗: $HTTP_CODE${NC}"
    echo "エラー: $BODY"
fi
echo ""

echo -e "${YELLOW}[TEST 6] ストリーミングテスト${NC}"
echo "ストリーミングレスポンス:"
curl -s -N \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "claude-haiku-4-5-20251001",
        "messages": [
            {
                "role": "user",
                "content": "3つの数字を数えてください"
            }
        ],
        "max_tokens": 50,
        "stream": true
    }' \
    "$BASE_URL/v1/chat/completions" | head -n 5

echo ""
echo -e "${GREEN}✓ ストリーミングテスト完了${NC}"
echo ""

echo "======================================"
echo "テスト完了"
echo "======================================"
echo ""
echo -e "${GREEN}すべてのテストが完了しました！${NC}"
echo ""
echo "次のステップ:"
echo "  1. Roo Code拡張機能をインストール"
echo "  2. 設定で以下を入力:"
echo "     - API Endpoint: http://litellm.nakacya.jp/v1"
echo "     - API Key: $TOKEN"
echo "  3. Roo Codeを使用してコーディング開始"
echo ""
