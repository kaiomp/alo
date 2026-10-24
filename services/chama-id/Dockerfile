# Build context is the repo root, so the pnpm lockfile is available.
FROM node:26-slim
WORKDIR /app
# Node 26 images no longer ship corepack.
RUN npm install -g pnpm@10.32.1
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY services/chama-id/package.json services/chama-id/
RUN pnpm install --filter chama-id --prod --frozen-lockfile
COPY services/chama-id/src services/chama-id/src
WORKDIR /app/services/chama-id
# A named volume mounted here inherits this ownership.
RUN mkdir /data && chown node:node /data
USER node
EXPOSE 8090
HEALTHCHECK --interval=5s --timeout=3s --retries=10 CMD node -e "fetch('http://127.0.0.1:8090/id/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.ts"]
