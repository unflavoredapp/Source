/** PM2 process file — run from this directory: `pm2 start ecosystem.config.cjs` */
module.exports = {
  apps: [
    {
      name: "unlicense-ipa-relay",
      script: "server.js",
      cwd: __dirname,
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "1G",
      kill_timeout: 10_000,
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
