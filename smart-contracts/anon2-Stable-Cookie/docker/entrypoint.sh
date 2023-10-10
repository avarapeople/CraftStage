#!/bin/sh

npx hardhat node &
sleep 5
npx hardhat run scripts/deploy.js --network localhost
sleep infinity
