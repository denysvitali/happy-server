# Multi-stage build for happy-server
# Stage 1: Building the application
FROM node:20-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++ git

WORKDIR /app

# Copy package files
COPY package.json yarn.lock ./
COPY ./prisma ./prisma

# Install dependencies
RUN yarn install --frozen-lockfile --ignore-engines

# Generate Prisma client
RUN yarn generate

# Copy the rest of the application code
COPY ./tsconfig.json ./tsconfig.json
COPY ./vitest.config.ts ./vitest.config.ts
COPY ./sources ./sources

# Build TypeScript application
RUN yarn build

# Stage 2: Runtime
FROM node:20-alpine AS runner

# Install runtime dependencies including tini for proper signal handling
RUN apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    tini

WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set environment to production
ENV NODE_ENV=production

# Copy package files
COPY package.json yarn.lock ./

# Install production dependencies only
RUN yarn install --production --frozen-lockfile --ignore-engines && \
    yarn cache clean

# Copy necessary files from the builder stage
COPY --from=builder --chown=nodejs:nodejs /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder --chown=nodejs:nodejs /app/tsconfig.json ./tsconfig.json
COPY --from=builder --chown=nodejs:nodejs /app/sources ./sources
COPY --from=builder --chown=nodejs:nodejs /app/prisma ./prisma

# Switch to non-root user
USER nodejs

# Expose the port the app will run on
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Use tini to handle signals properly
ENTRYPOINT ["/sbin/tini", "--"]

# Command to run the application
CMD ["yarn", "start"] 