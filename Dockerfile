FROM python:3.13-slim-bookworm AS base

# 使用国内镜像源加速
# 替换 Debian apt 源为清华大学镜像
RUN sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN apt-get update && apt-get install -y curl gnupg git build-essential \
  && curl -fsSL https://registry.npmmirror.com/-/binary/node/v22.14.0/node-v22.14.0-linux-x64.tar.xz -o /tmp/node.tar.xz \
  && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.xz \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# 配置 npm 和 pnpm 为淘宝镜像
RUN npm config set registry https://registry.npmmirror.com \
  && npm config set @pnpm:registry https://registry.npmmirror.com \
  && npm install -g pnpm \
  && pnpm config set registry https://registry.npmmirror.com

ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN mkdir -p $PNPM_HOME && \
  pnpm add -g @amap/amap-maps-mcp-server @playwright/mcp@latest tavily-mcp@latest @modelcontextprotocol/server-github @modelcontextprotocol/server-slack

ARG INSTALL_EXT=false
RUN if [ "$INSTALL_EXT" = "true" ]; then \
  ARCH=$(uname -m); \
  if [ "$ARCH" = "x86_64" ]; then \
  # 使用国内镜像安装 Playwright 浏览器 \
  PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright npx -y playwright install --with-deps chrome firefox; \
  else \
  echo "Skipping Chrome and Firefox installation on non-amd64 architecture: $ARCH"; \
  fi; \
  # Install Docker Engine (使用阿里云镜像) \
  apt-get update && \
  apt-get install -y ca-certificates curl iptables && \
  install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
  chmod a+r /etc/apt/keyrings/docker.asc && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/debian bookworm stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  apt-get update && \
  apt-get install -y docker-ce docker-ce-cli containerd.io && \
  apt-get clean && rm -rf /var/lib/apt/lists/*; \
  fi

# 使用 uv 中国镜像
RUN UV_PYTHON_INSTALL_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/python-release uv tool install mcp-server-fetch

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
# 使用淘宝镜像安装依赖
RUN pnpm install --registry https://registry.npmmirror.com

COPY . .

# Download the latest servers.json from mcpm.sh (使用国内 CDN 如果可用)
RUN curl -s -f --connect-timeout 10 https://mcpm.sh/api/servers.json -o servers.json || echo "Failed to download servers.json, using bundled version"

RUN pnpm frontend:build && pnpm build

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["pnpm", "start"]
