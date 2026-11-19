FROM node:22-alpine
WORKDIR /app
COPY package.json relay.mjs server.mjs brawlstars.mjs ./
USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.mjs"]
