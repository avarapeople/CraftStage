# aave-streams

## Overview

This project is integration between token streaming protocol(Sablier in this case) and AAVE. Token Streaming Protocols streams tokens every second. It is commonly observed that stream receiver doesn't claim the token daily(regularly) but when it reaches certain volume or if they are in need. So, the idea of this project is to deposit this unclaimed tokens to AAVE so that it automatically earns yield and are not considered to be dead assets. Gelato bots are used for triggering transaction at regular interval.

## Flow diagram

![Screenshot](/Screenshot.jpeg)

## Contracts overview

### LockupLinearStreamCreator

`createLockupLinearStream`: creates the linear stream. This will generally be used to create stream to the `LinearStreamReceiver` contract which automatically deposits to AAVE with help of Gelato bots.

### LinearStreamReceiver

`withdraw`: This is used to withdraw the tokens gathered from the stream till now. It also allows partial withdraw of unclaimed tokens. Only owner can call this function.

`withdrawMax`: This is used to withdraw all the tokens gathered from the stream till now. Only owner can call this function.

`withdrawAndSupplyOnAave`: This function is used to withdraw all the tokens gathered from the stream till now and supply it on AAVE to earn yield. `LinearStreamReceiver` contract will receive `aTokens` for the tokens deposited. This function is supposed to be called by Gelato bots at regular interval.

`withdrawFromAave`: This function is used to withdraw the tokens deposited from AAVE and send it to the caller specified address. Only owner can call this function.

`updateDedicatedMsgSender`: This function is used to update the address of Gelato bots which has permission to call `withdrawAndSupplyOnAave`.

## Setup and tests

* Make sure you have foundry installed.
* Make `.env` file and populate the environment variable mentioned in `.env.example`.
* Run `forge test` to run the tests.





