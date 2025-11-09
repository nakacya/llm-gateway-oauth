FROM openresty/openresty:alpine

# 必要なツールをインストール
RUN apk add --no-cache git tcpdump curl

# 作業ディレクトリ
WORKDIR /tmp

# lua-resty-jwtのインストール
RUN git clone https://github.com/SkyLothar/lua-resty-jwt.git && \
    cd lua-resty-jwt && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/ && \
    cd .. && \
    rm -rf lua-resty-jwt

# lua-resty-hmacのインストール
RUN git clone https://github.com/jkeys089/lua-resty-hmac.git && \
    cd lua-resty-hmac && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/ && \
    cd .. && \
    rm -rf lua-resty-hmac

# lua-resty-stringのインストール
RUN git clone https://github.com/openresty/lua-resty-string.git && \
    cd lua-resty-string && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/ && \
    cd .. && \
    rm -rf lua-resty-string

# lua-resty-httpのインストール
RUN git clone https://github.com/ledgetech/lua-resty-http.git && \
    cd lua-resty-http && \
    cp -r lib/resty/* /usr/local/openresty/lualib/resty/ && \
    cd .. && \
    rm -rf lua-resty-http

# 必要なディレクトリを作成
RUN mkdir -p /usr/local/openresty/nginx/html && \
    mkdir -p /var/log/nginx && \
    chmod 755 /usr/local/openresty/nginx/html && \
    chmod 755 /var/log/nginx

# gitは不要なので削除（イメージサイズ削減）
RUN apk del git

# 作業ディレクトリをクリーンアップ
WORKDIR /usr/local/openresty

# ヘルスチェック
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# デフォルトコマンド
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
