FROM node:24-bookworm
ENV DEBIAN_FRONTEND=noninteractive HOME=/opt/claw
RUN apt-get update && apt-get install -y --no-install-recommends git curl python3 python3-pip ffmpeg ca-certificates && apt-get clean
RUN npm i -g openclaw@latest
RUN mkdir -p /opt/claw && git clone --depth 1 https://github.com/tashfeenahmed/freellmapi /opt/claw/freellmapi \
 && cd /opt/claw/freellmapi/server && npm install --no-audit --no-fund && npm run build
RUN pip3 install --break-system-packages -q yt-dlp faster-whisper
COPY render-boot.sh /render-boot.sh
RUN chmod +x /render-boot.sh
CMD ["bash","/render-boot.sh"]
