FROM node:20-bookworm-slim
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY server.js telegramUser.js login.js ecosystem.config.cjs .env.example ./
RUN mkdir -p /data

ENV DATA_DIR=/data
ENV PORT=8787
ENV MAX_BYTES=4294967296
EXPOSE 8787
VOLUME ["/data"]
CMD ["node", "server.js"]
