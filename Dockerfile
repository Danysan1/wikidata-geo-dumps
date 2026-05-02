FROM node:25.0-alpine3.22
WORKDIR /workdir
COPY package* /workdir/
RUN npm install
