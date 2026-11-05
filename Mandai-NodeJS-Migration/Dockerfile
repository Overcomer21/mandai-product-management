
# Mandai Product Management - Node.js
# Node.js 22 LTS
# Internal service port: 8011

FROM node:22-bookworm-slim

WORKDIR /app

# Install production dependencies
COPY package*.json ./

RUN npm install --omit=dev --ignore-scripts=false

# Copy application source
COPY src ./src

# Copy SQL Server validation scripts
COPY scripts ./scripts

# Runtime configuration
ENV NODE_ENV=production
ENV PORT=8011

# Run as non-root user
USER node

# Node.js internal port
EXPOSE 8011

CMD ["node", "src/server.js"]
