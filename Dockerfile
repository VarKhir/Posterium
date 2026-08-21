FROM node:20-bookworm AS source
WORKDIR /src
ARG SOURCE_REPO=https://github.com/VarKhir/Posterium.git
ARG SOURCE_REF=master
COPY . .
RUN if [ ! -f package.json ]; then \
      apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/* && \
      git clone --depth 1 --branch "$SOURCE_REF" "$SOURCE_REPO" /tmp/posterium && \
      cp -a /tmp/posterium/. .; \
    fi && test -f package.json
# Rimuove la cartella dei test per evitare errori di tipo/linting in fase di compilazione
RUN rm -rf src/__tests__ __tests__

FROM node:20-bookworm AS deps
WORKDIR /app
COPY --from=source /src/package.json /src/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM node:20-bookworm AS builder
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=source /src/package.json /src/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY --from=source /src ./
# Compila Next.js saltando controlli di tipo e linting
RUN npx next build --no-lint

FROM node:20-bookworm AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=8080
ENV HOSTNAME=0.0.0.0
ARG NODE_MAX_OLD_SPACE=384
ENV NODE_OPTIONS="--max-old-space-size=${NODE_MAX_OLD_SPACE}"
ENV SHARP_CONCURRENCY=2
ENV SHARP_CACHE_MEMORY_MB=64
ENV POSTERIUM_DATA_DIR=/data

# Rimuove l'utente preesistente 'node' (UID 1000)
RUN userdel -r node && addgroup --system nodejs && adduser --system --uid 1000 nextjs

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder /app/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /data && chown nextjs:nodejs /data

USER nextjs

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 8080) + '/api/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["/entrypoint.sh"]
