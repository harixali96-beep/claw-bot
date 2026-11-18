FROM node:22-bookworm
ENV DEBIAN_FRONTEND=noninteractive HOME=/opt/claw
RUN apt-get update && apt-get install -y --no-install-recommends git curl python3 python3-pip ffmpeg ca-certificates && apt-get clean
RUN npm i -g openclaw@latest
RUN mkdir -p /opt/claw && git clone --depth 1 https://github.com/tashfeenahmed/freellmapi /opt/claw/freellmapi \
 && cd /opt/claw/freellmapi/server && npm install --no-audit --no-fund && npm run build
RUN pip3 install --break-system-packages -q yt-dlp faster-whisper
RUN curl -fsSL -o /start.sh https://base44.app/api/apps/6afd5d7f94aa00438e512b21/files/mp/public/6afd5d7f94aa00438e512b21/2a63d8608_start-oc.sh && chmod +x /start.sh
RUN chmod -R 777 /opt/claw
CMD ["bash","/start.sh"]
