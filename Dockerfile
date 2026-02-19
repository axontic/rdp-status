FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --only=production

COPY . .

FROM node:20-alpine

WORKDIR /app

COPY --from=builder /app /app

ENV PORT=3000 \
    HEARTBEAT_MS=60000 \
    OFFLINE_MS=150000 \
    CONSOLE_BUSY=false \
    USE_CLIENT_OCCUPANCY=true

EXPOSE 3000

CMD ["node", "server.js"]

