# Use an official Node.js LTS version as the base image
FROM node:lts

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and yarn.lock to the container
COPY package*.json ./

# Install project dependencies
RUN yarn install

# Copy the entire project to the container
COPY . .

# Expose the necessary port for the Hardhat network (e.g., 8545)
EXPOSE 8545

CMD ["npx", "hardhat", "node"]
