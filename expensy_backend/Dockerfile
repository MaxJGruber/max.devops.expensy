# ---------- Builder ----------
FROM node:20-alpine AS builder
WORKDIR /app

# Install deps first (better caching)
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---------- Runtime ----------
FROM node:20-alpine AS runtime
WORKDIR /app

# Install only production deps
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled output
COPY --from=builder /app/dist ./dist

# If your app loads .env at runtime, you normally DON'T bake it in.
# Use env vars in Docker/Kubernetes instead.

EXPOSE 8706
CMD ["node", "dist/server.js"]
