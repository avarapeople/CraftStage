// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "../contracts/veNFT.sol";
import "../contracts/MockToken.sol";

contract Deployment is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contracts
        MockToken mockToken = new MockToken();
        VeNFT venft = new VeNFT(address(mockToken));

        vm.stopBroadcast();
    }
}