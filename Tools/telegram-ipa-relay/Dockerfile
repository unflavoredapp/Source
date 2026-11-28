FROM node:20-bookworm-slim
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

COPY package.json server.js send_user.py login.py requirements.txt ./
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt \
  && mkdir -p /data

ENV DATA_DIR=/data
ENV PORT=8787
ENV MAX_BYTES=4294967296
EXPOSE 8787
VOLUME ["/data"]
CMD ["node", "server.js"]
