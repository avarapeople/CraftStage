pragma solidity ^0.8.17;

import { Test, console } from "forge-std/Test.sol";
import { LinearStreamReceiver } from "src/LinearStreamReceiver.sol";
import { LockupLinearStreamCreator } from "src/LockupLinearStreamCreator.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2Lockup } from "@sablier/v2-core/interfaces/ISablierV2Lockup.sol";
import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";

contract LinearStreamReceiverTest is Test {

    address public owner = makeAddr("owner");
    address public dedicatedMsgSender = makeAddr("dedicatedMsgSender");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    LockupLinearStreamCreator public lockupLinearStreamCreator;
    LinearStreamReceiver public linearStreamReceiver;
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL, 177_11_185);
        vm.startPrank(owner);
        lockupLinearStreamCreator = new LockupLinearStreamCreator(ISablierV2LockupLinear(0xB10daee1FCF62243aE27776D7a92D39dC8740f95));
        linearStreamReceiver = new LinearStreamReceiver(ISablierV2Lockup(0xB10daee1FCF62243aE27776D7a92D39dC8740f95), dedicatedMsgSender);
        vm.stopPrank();

        deal(address(DAI), alice, 1e6 * 1e18, true);
        deal(address(DAI), bob, 1e6 * 1e18, true);
    }

    function test_create_stream() public {
        vm.startPrank(alice);
        DAI.approve(address(lockupLinearStreamCreator), type(uint256).max);
        lockupLinearStreamCreator.createLockupLinearStream(address(linearStreamReceiver), 1000 * 1e18, 4 weeks, 52 weeks);
    }

    function test_owner_can_withdraw_from_created_stream() public {
        vm.startPrank(alice);
        DAI.approve(address(lockupLinearStreamCreator), type(uint256).max);
        uint256 streamId = lockupLinearStreamCreator.createLockupLinearStream(address(linearStreamReceiver), 1000 * 1e18, 4 weeks, 52 weeks);
        vm.stopPrank();

        skip(4 weeks);

        vm.startPrank(owner);
        uint256 daiBalanceBefore = DAI.balanceOf(owner);
        linearStreamReceiver.withdraw(streamId, owner, 3 * 1e18);
        uint256 daiBalanceAfter = DAI.balanceOf(owner);
        assertEq(daiBalanceAfter - daiBalanceBefore, 3 * 1e18);
    }

    function test_owner_can_withdraw_max_from_created_stream() public {
        vm.startPrank(alice);
        DAI.approve(address(lockupLinearStreamCreator), type(uint256).max);
        uint256 streamId = lockupLinearStreamCreator.createLockupLinearStream(address(linearStreamReceiver), 1000 * 1e18, 4 weeks, 52 weeks);
        vm.stopPrank();

        skip(52 weeks);

        vm.startPrank(owner);
        uint256 daiBalanceBefore = DAI.balanceOf(owner);
        linearStreamReceiver.withdrawMax(streamId, owner);
        uint256 daiBalanceAfter = DAI.balanceOf(owner);
        assertEq(daiBalanceAfter - daiBalanceBefore, 1000 * 1e18);
    }

    function test_supplying_on_aave_earns_yield() public {

        vm.startPrank(alice);
        DAI.approve(address(lockupLinearStreamCreator), type(uint256).max);
        uint256 streamId = lockupLinearStreamCreator.createLockupLinearStream(address(linearStreamReceiver), 1000 * 1e18, 4 weeks, 52 weeks);
        vm.stopPrank();

        skip(52 weeks);

        vm.startPrank(dedicatedMsgSender);
        uint256 daiBalanceBefore = DAI.balanceOf(owner);
        linearStreamReceiver.withdrawAndSupplyOnAave(streamId);
        vm.stopPrank();

        skip(52 weeks);

        vm.startPrank(owner);
        linearStreamReceiver.withdrawFromAave(type(uint256).max, owner);
        uint256 daiBalanceAfter = DAI.balanceOf(owner);
        assertGt(daiBalanceAfter - daiBalanceBefore, 1000 * 1e18);
    }
}