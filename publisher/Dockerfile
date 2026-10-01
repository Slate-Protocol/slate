# Slate publisher: Node 24 runs the TypeScript sources directly (type stripping), no build step.
FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY src ./src
CMD ["node", "src/main.ts"]
