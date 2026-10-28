# Build context is the repo root, so the pnpm lockfile is available.
FROM node:26.12.1-slim
WORKDIR /app
# Node 26 images no longer ship corepack.
RUN npm install -g pnpm@10.32.1
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY services/alo-id/package.json services/alo-id/
RUN pnpm install --filter alo-id --prod --frozen-lockfile
COPY services/alo-id/src services/alo-id/src
WORKDIR /app/services/alo-id
# A named volume mounted here inherits this ownership.
RUN mkdir /data && chown node:node /data
USER node
EXPOSE 8090
HEALTHCHECK --interval=5s --timeout=3s --retries=10 CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8090)+'/id/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.ts"]
