pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract BaseTest is Test {
    // Define global constants | Test config
    // @dev Make it 0 to test on latest
    uint256 public constant NUM_ACTORS = 5;

    address[] public actors;
    address internal currentActor;
    
    /// @notice Get a pre-set address for prank
    /// @param actorIndex Index of the actor
    modifier useActor(uint256 actorIndex) {
        currentActor = actors[bound(actorIndex, 0, actors.length -1)];
        vm.startPrank(currentActor, currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Start a prank session with a known user addr
    modifier useKnownActor(address user) {
        currentActor = user;
        vm.startPrank(currentActor, currentActor);
        _;
        vm.stopPrank();
    } 

    /// @notice Initialize global test configuration.
    function setUp() virtual public {
        
        /// @dev Initialize actors for testing. 
        for(uint256 i = 0; i < NUM_ACTORS; ++i) {
            actors.push(makeAddr(Strings.toString(i)));
        }
    }
}