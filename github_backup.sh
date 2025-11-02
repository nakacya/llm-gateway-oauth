#!/bin/bash
# github_backup.sh (v2)
# システムをGitHubにバックアップする自動化スクリプト
#
# v2の変更点:
# - create_all_samples.shを使用して全設定ファイルをサンプル化
# - oauth2_proxy.cfg.sample, litellm_config.yaml.sampleにも対応

set -e

# 色付きメッセージ用
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GitHub バックアップスクリプト v2${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ========================================
# ステップ0: カレントディレクトリ確認
# ========================================
echo -e "${YELLOW}[0/8] 現在のディレクトリを確認しています...${NC}"
CURRENT_DIR=$(pwd)
echo "カレントディレクトリ: $CURRENT_DIR"

if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}エラー: docker-compose.ymlが見つかりません${NC}"
    echo "プロジェクトのルートディレクトリで実行してください"
    exit 1
fi

echo -e "${GREEN}✓ docker-compose.ymlを確認${NC}"
echo ""

# ========================================
# ステップ1: サンプルファイルの生成
# ========================================
echo -e "${YELLOW}[1/8] サンプルファイルを生成しています...${NC}"

# create_all_samples.shがあるか確認
if [ -f "create_all_samples.sh" ]; then
    chmod +x create_all_samples.sh
    ./create_all_samples.sh
elif [ -f "scripts/create_all_samples.sh" ]; then
    chmod +x scripts/create_all_samples.sh
    cd scripts && ./create_all_samples.sh && cd ..
# 旧スクリプトとの互換性
elif [ -f "create_env_sample.sh" ]; then
    echo -e "${YELLOW}  create_all_samples.shが見つかりません。create_env_sample.shを使用します${NC}"
    chmod +x create_env_sample.sh
    ./create_env_sample.sh
else
    echo -e "${YELLOW}  警告: サンプル生成スクリプトが見つかりません${NC}"
    echo -e "${YELLOW}  手動でサンプルファイルを作成してください:${NC}"
    echo "    - .env → .env_sample"
    echo "    - oauth2_proxy.cfg → oauth2_proxy.cfg.sample"
    echo "    - litellm_config.yaml → litellm_config.yaml.sample"
    echo ""
    echo "続行しますか? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "キャンセルしました"
        exit 0
    fi
fi

echo -e "${GREEN}✓ サンプルファイル生成完了${NC}"
echo ""

# ========================================
# ステップ2: .gitignoreの確認
# ========================================
echo -e "${YELLOW}[2/8] .gitignoreを確認しています...${NC}"

if [ ! -f ".gitignore" ]; then
    echo -e "${YELLOW}.gitignoreが見つかりません。作成しますか? (y/n)${NC}"
    read -r response
    if [[ "$response" == "y" ]]; then
        cat > .gitignore << 'EOF'
# 機密情報
.env
oauth2_proxy.cfg
litellm_config.yaml
*.key
*.pem

# サンプルファイルは含める
!.env_sample
!oauth2_proxy.cfg.sample
!litellm_config.yaml.sample

# Docker
data/
volumes/

# バックアップ
backup/
backup_*/
*.bak

# ログ
*.log
logs/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
EOF
        echo -e "${GREEN}✓ .gitignore作成完了${NC}"
    fi
else
    # .gitignoreに必要な項目が含まれているか確認
    if ! grep -q ".env_sample" .gitignore 2>/dev/null; then
        echo -e "${YELLOW}  .gitignoreに.env_sampleの除外設定がありません${NC}"
        echo -e "${YELLOW}  追加しますか? (y/n)${NC}"
        read -r response
        if [[ "$response" == "y" ]]; then
            cat >> .gitignore << 'EOF'

# サンプルファイルは含める
!.env_sample
!oauth2_proxy.cfg.sample
!litellm_config.yaml.sample
EOF
            echo -e "${GREEN}  ✓ .gitignoreを更新${NC}"
        fi
    fi
    echo -e "${GREEN}✓ .gitignore確認完了${NC}"
fi

echo ""

# ========================================
# ステップ3: Gitリポジトリの確認
# ========================================
echo -e "${YELLOW}[3/8] Gitリポジトリを確認しています...${NC}"

if [ ! -d ".git" ]; then
    echo -e "${YELLOW}Gitリポジトリが初期化されていません${NC}"
    echo "Gitリポジトリを初期化しますか? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
        git init
        echo -e "${GREEN}✓ Gitリポジトリ初期化完了${NC}"
    else
        echo -e "${RED}エラー: Gitリポジトリが必要です${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Gitリポジトリ確認完了${NC}"
fi

echo ""

# ========================================
# ステップ4: GitHubリモートの設定確認
# ========================================
echo -e "${YELLOW}[4/8] GitHubリモートを確認しています...${NC}"

if ! git remote | grep -q origin; then
    echo -e "${YELLOW}GitHubリモートが設定されていません${NC}"
    echo ""
    echo "GitHubリポジトリのURLを入力してください:"
    echo "例: https://github.com/username/repo.git"
    echo "または: git@github.com:username/repo.git"
    read -r repo_url
    
    if [ -n "$repo_url" ]; then
        git remote add origin "$repo_url"
        echo -e "${GREEN}✓ リモート追加完了: $repo_url${NC}"
    else
        echo -e "${YELLOW}リモートの設定をスキップしました${NC}"
        echo "後で手動で設定してください: git remote add origin <URL>"
    fi
else
    REMOTE_URL=$(git remote get-url origin)
    echo -e "${GREEN}✓ リモート確認完了: $REMOTE_URL${NC}"
fi

echo ""

# ========================================
# ステップ5: ステージングするファイルの確認
# ========================================
echo -e "${YELLOW}[5/8] ステージングするファイルを確認しています...${NC}"

echo ""
echo "以下のファイルをGitHubにアップロードします:"
echo ""

# 重要なファイルのリスト
IMPORTANT_FILES=(
    "docker-compose.yml"
    ".env_sample"
    "oauth2_proxy.cfg.sample"
    "litellm_config.yaml.sample"
    "nginx.conf"
    "README.md"
    ".gitignore"
)

for file in "${IMPORTANT_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file"
    else
        echo -e "  ${YELLOW}?${NC} $file (見つかりません)"
    fi
done

echo ""
echo "lua/ディレクトリ:"
if [ -d "lua" ]; then
    ls lua/*.lua 2>/dev/null | while read -r file; do
        echo -e "  ${GREEN}✓${NC} $file"
    done || echo -e "  ${YELLOW}?${NC} Luaファイルが見つかりません"
else
    echo -e "  ${YELLOW}?${NC} lua/ (ディレクトリが見つかりません)"
fi

echo ""
echo "docs/ディレクトリ:"
if [ -d "docs" ]; then
    ls docs/*.md 2>/dev/null | while read -r file; do
        echo -e "  ${GREEN}✓${NC} $file"
    done || echo -e "  ${YELLOW}?${NC} ドキュメントが見つかりません"
else
    echo -e "  ${YELLOW}?${NC} docs/ (ディレクトリが見つかりません)"
fi

echo ""
echo "scripts/ディレクトリ:"
if [ -d "scripts" ]; then
    ls scripts/*.sh 2>/dev/null | while read -r file; do
        echo -e "  ${GREEN}✓${NC} $file"
    done || echo -e "  ${YELLOW}?${NC} スクリプトが見つかりません"
else
    echo -e "  ${YELLOW}?${NC} scripts/ (ディレクトリが見つかりません)"
fi

echo ""
echo -e "${RED}以下のファイルは除外されます（機密情報）:${NC}"
echo -e "  ${RED}✗${NC} .env"
echo -e "  ${RED}✗${NC} oauth2_proxy.cfg (実際の値を含むもの)"
echo -e "  ${RED}✗${NC} litellm_config.yaml (実際の値を含むもの)"
echo -e "  ${RED}✗${NC} data/, backup/, logs/"

echo ""
echo -e "${YELLOW}これらのファイルをコミットしますか? (y/n)${NC}"
read -r response

if [[ "$response" != "y" ]]; then
    echo "キャンセルしました"
    exit 0
fi

echo ""

# ========================================
# ステップ6: ファイルをステージング
# ========================================
echo -e "${YELLOW}[6/8] ファイルをステージングしています...${NC}"

# 全てのファイルを追加（.gitignoreで除外されるものは自動的に除外される）
git add .

# ステータス確認
echo ""
echo "ステージングされたファイル:"
git status --short

# 機密ファイルが含まれていないか警告チェック
echo ""
echo -e "${YELLOW}機密ファイルチェック...${NC}"
if git status --short | grep -E "^\s*[AM].*(\.env$|oauth2_proxy\.cfg$|litellm_config\.yaml$)" | grep -v "\.sample"; then
    echo -e "${RED}警告: 機密ファイルがステージングされています！${NC}"
    echo -e "${RED}以下のファイルを除外してください:${NC}"
    git status --short | grep -E "^\s*[AM].*(\.env$|oauth2_proxy\.cfg$|litellm_config\.yaml$)" | grep -v "\.sample"
    echo ""
    echo "続行しますか? (y/n)"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo "キャンセルしました"
        exit 1
    fi
else
    echo -e "${GREEN}✓ 機密ファイルは含まれていません${NC}"
fi

echo ""
echo -e "${GREEN}✓ ステージング完了${NC}"
echo ""

# ========================================
# ステップ7: コミット
# ========================================
echo -e "${YELLOW}[7/8] 変更をコミットしています...${NC}"

# コミットメッセージの入力
echo ""
echo "コミットメッセージを入力してください:"
echo "（空欄の場合は自動生成されます）"
read -r commit_message

if [ -z "$commit_message" ]; then
    # 自動生成されたコミットメッセージ
    commit_message="Update LiteLLM Gateway configuration - $(date '+%Y-%m-%d %H:%M:%S')"
fi

# コミット
if git diff --cached --quiet; then
    echo -e "${YELLOW}コミットする変更がありません${NC}"
else
    git commit -m "$commit_message"
    echo -e "${GREEN}✓ コミット完了${NC}"
fi

echo ""

# ========================================
# ステップ8: GitHubへプッシュ
# ========================================
echo -e "${YELLOW}[8/8] GitHubへプッシュしています...${NC}"

# ブランチ名を取得
CURRENT_BRANCH=$(git branch --show-current)

if [ -z "$CURRENT_BRANCH" ]; then
    CURRENT_BRANCH="main"
    git branch -M main
fi

echo "ブランチ: $CURRENT_BRANCH"

# プッシュ確認
echo ""
echo -e "${YELLOW}GitHubへプッシュしますか? (y/n)${NC}"
read -r response

if [[ "$response" == "y" ]]; then
    # リモートが設定されているか確認
    if ! git remote | grep -q origin; then
        echo -e "${RED}エラー: リモートが設定されていません${NC}"
        echo "以下のコマンドでリモートを追加してください:"
        echo "  git remote add origin <GitHub URL>"
        exit 1
    fi
    
    # プッシュ
    echo "プッシュ中..."
    if git push -u origin "$CURRENT_BRANCH"; then
        echo -e "${GREEN}✓ プッシュ完了${NC}"
    else
        echo -e "${YELLOW}プッシュに失敗しました${NC}"
        echo ""
        echo "初回プッシュの場合は、GitHubで空のリポジトリを作成してから再度実行してください"
        echo ""
        echo "または、強制プッシュする場合:"
        echo "  git push -u origin $CURRENT_BRANCH --force"
    fi
else
    echo "プッシュをスキップしました"
    echo ""
    echo "後で手動でプッシュする場合:"
    echo "  git push -u origin $CURRENT_BRANCH"
fi

echo ""

# ========================================
# 完了メッセージ
# ========================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}バックアップ完了！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# リモートURLを表示
if git remote | grep -q origin; then
    REMOTE_URL=$(git remote get-url origin)
    echo -e "${GREEN}GitHubリポジトリ:${NC}"
    echo "  $REMOTE_URL"
    echo ""
fi

# 含まれているサンプルファイルを表示
echo -e "${GREEN}GitHubに含まれるサンプルファイル:${NC}"
[ -f ".env_sample" ] && echo "  ✓ .env_sample"
[ -f "oauth2_proxy.cfg.sample" ] && echo "  ✓ oauth2_proxy.cfg.sample"
[ -f "litellm_config.yaml.sample" ] && echo "  ✓ litellm_config.yaml.sample"
[ -f "docker-compose.yml.sample" ] && echo "  ✓ docker-compose.yml.sample"

echo ""

# 次のステップ案内
echo -e "${YELLOW}次のステップ:${NC}"
echo ""
echo "1. GitHubでリポジトリを確認:"
if git remote | grep -q origin; then
    REMOTE_URL=$(git remote get-url origin)
    # URL変換（git@からhttpsへ）
    if [[ "$REMOTE_URL" == git@github.com:* ]]; then
        HTTPS_URL=$(echo "$REMOTE_URL" | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
        echo "   $HTTPS_URL"
    else
        echo "   $REMOTE_URL"
    fi
fi
echo ""

echo "2. 新しい環境でのセットアップ:"
echo "   git clone <リポジトリURL>"
echo "   cd <リポジトリ名>"
echo "   cp .env_sample .env"
echo "   cp oauth2_proxy.cfg.sample oauth2_proxy.cfg"
echo "   cp litellm_config.yaml.sample litellm_config.yaml"
echo "   vi .env oauth2_proxy.cfg litellm_config.yaml  # 実際の値を設定"
echo ""

echo "3. 定期的にバックアップを実行:"
echo "   ./github_backup.sh"
echo ""

# 統計情報
echo -e "${YELLOW}統計情報:${NC}"
echo "  コミット数: $(git rev-list --count HEAD 2>/dev/null || echo '0')"
echo "  管理ファイル数: $(git ls-files | wc -l)"
echo "  最新コミット: $(git log -1 --pretty=format:'%h - %s' 2>/dev/null || echo 'なし')"
echo ""

echo -e "${GREEN}完了！${NC}"
