FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
RUN mkdir -p /data
ENV DATA_DIR=/data
ENV PORT=8787
EXPOSE 8787
VOLUME ["/data"]
CMD ["node", "server.js"]
