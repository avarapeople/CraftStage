//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.18;

import {BaseTest} from "./BaseTest.t.sol";
import {MockToken} from "../contracts/MockToken.sol";
import {VeNFT} from "../contracts/VeNFT.sol";
import "forge-std/console.sol";


contract VeNFT_Base is BaseTest {
    uint256 public constant WEEK = 1 weeks;
    
    VeNFT public venft;
    MockToken public mockToken;
    uint128 baseDepositAmt;
    uint256 baseLockTime;
    uint256 actorId = 0;
    uint256 secondaryActor = 1;

    event TokenCheckpoint(
        VeNFT.ActionType indexed actionType,
        address indexed user,
        uint256 indexed tokenId,
        uint256 value,
        uint256 locktime
    );
    event GlobalCheckpoint(address caller, uint256 epoch);
    event Withdraw(address indexed user, uint256 indexed tokenId, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    function setUp() public virtual override {
        super.setUp();
        mockToken = new MockToken();
        venft = new VeNFT(address(mockToken));
        vm.warp(1687025783);

        // Set test configuration.
        baseDepositAmt = 1000e18;
        baseLockTime = ((block.timestamp + 4 weeks) / WEEK) * WEEK;
        mockToken.mint(actors[actorId], type(uint128).max);
        mockToken.mint(actors[secondaryActor], type(uint128).max);
    }

    function _createLock() internal returns(uint256 tokenId){
        mockToken.approve(address(venft), type(uint128).max);
        venft.createLock(baseDepositAmt, baseLockTime);
        tokenId = venft.tokenOfOwnerByIndex(actors[actorId], 0);
    }
}

contract VeNFT_CreateLock_Test is VeNFT_Base {
    function test_createLock(uint128 value, uint256 time) public useActor(0) {
        address actor = actors[0];
        uint256 nextWeek = ((block.timestamp + WEEK)/WEEK) * WEEK;
        vm.assume(value > 0);
        time = uint256(bound(time, nextWeek, block.timestamp + venft.MAX_TIME()));
        mockToken.approve(address(venft), value);

        vm.expectEmit(true, true, true, true);
        emit TokenCheckpoint(
            VeNFT.ActionType.CREATE_LOCK,
            actor,
            1,
            value,
            (time / WEEK) * WEEK
        );
        venft.createLock(value, time);
        assertEq(venft.balanceOfUser(actor), venft.balanceOfToken(1));
        assertEq(venft.balanceOf(actor), 1);
    }

    function test_revertsWhen_with0Val() public useActor(0) {
        vm.expectRevert("Cannot lock 0 tokens");
        venft.createLock(0, block.timestamp + WEEK);
    }

    function test_revertsWhen_lockInPast() public useActor(0) {
        vm.expectRevert("Cannot lock in the past");
        venft.createLock(1e18, 0);
    }

    function test_revertsWhen_lockGreaterThanMax() public useActor(0) {
        uint256 time = block.timestamp + venft.MAX_TIME() + 10 weeks;
        vm.expectRevert("Voting lock can be 4 years max");
        venft.createLock(1e18, time);
    }
}

contract VeNFT_IncreaseAmount_Test is VeNFT_Base {
    
    function test_increaseAmount(uint128 value) public useActor(actorId){
        value = uint128(bound(value, 1, type(uint128).max - baseDepositAmt));
        uint256 tokenId = _createLock();
        address actor = actors[0];
        vm.expectEmit(true, true, true, true);
        emit TokenCheckpoint(
            VeNFT.ActionType.INCREASE_AMOUNT,
            actor,
            tokenId,
            value,
            baseLockTime
        );
        venft.increaseAmount(tokenId, value);
    }

    function test_revertsWhen_userNotOwner() public useActor(actorId) {
        uint256 tokenId = _createLock();
        changePrank(actors[1]);
        vm.expectRevert("Unauthorized request");
        venft.increaseAmount(tokenId, 2e18);
    }

    function test_revertsWhen_with0Val() public useActor(actorId) {
        uint256 tokenId = _createLock();
        vm.expectRevert("Cannot deposit 0 tokens");
        venft.increaseAmount(tokenId, 0);
    }

    // Redundant test, buring of the nft token checks this out.
    // function test_revertsWhen_lockDoesNotExist() public useActor(actorId) {
    //     uint256 tokenId = _createLock(2e18);
    //     vm.warp(venft.lockedEnd(tokenId) + 1);
    //     venft.withdraw(tokenId);
    //     vm.expectRevert("No existing lock found");
    //     venft.increaseAmount(tokenId, 2e18);
    // }

    function test_revertsWhen_lockExpired() public useActor(actorId) {
        uint256 tokenId = _createLock();
        vm.warp(venft.lockedEnd(tokenId) + 1);
        vm.expectRevert("Lock expired. Withdraw");
        venft.increaseAmount(tokenId, 2e18);
    }
}

contract VeNFT_DepositFor_Test is VeNFT_Base {
    function test_depositFor(uint128 value) public useActor(actorId){
        value = uint128(bound(value, 1, type(uint128).max - baseDepositAmt));
        uint256 tokenId = _createLock();
        changePrank(actors[secondaryActor]);
        mockToken.approve(address(venft), value);
        vm.expectEmit(true, true, true, true);
        emit TokenCheckpoint(
            VeNFT.ActionType.DEPOSIT_FOR,
            actors[actorId],
            tokenId,
            value,
            baseLockTime
        );
        venft.depositFor(actors[actorId], tokenId, value);
    }

    function test_revertsWhen_userNotOwner() public useActor(actorId) {
        uint256 tokenId = _createLock();
        changePrank(actors[secondaryActor]);
        vm.expectRevert("Invalid request");
        venft.depositFor(actors[secondaryActor], tokenId, baseDepositAmt);
    }

    function test_revertsWhen_with0Val() public useActor(actorId) {
        uint256 tokenId = _createLock();
        changePrank(actors[secondaryActor]);
        vm.expectRevert("Cannot deposit 0 tokens");
        venft.depositFor(actors[actorId], tokenId, 0);
    }

    function test_revertsWhen_lockExpired() public useActor(actorId) {
        uint256 tokenId = _createLock();
        vm.warp(venft.lockedEnd(tokenId) + 1);
        changePrank(actors[secondaryActor]);
        vm.expectRevert("Lock expired. Withdraw");
        venft.depositFor(actors[actorId], tokenId, baseDepositAmt);
    }
}

contract VeNFT_IncreaseUnlockTime_Test is VeNFT_Base {
    function test_increaseUnlockTime(uint256 time) public useActor(actorId){
        uint256 tokenId = _createLock();
        time = uint256(bound(time, venft.lockedEnd(tokenId) + 1 weeks, block.timestamp + venft.MAX_TIME()));
        vm.expectEmit(true, true, true, true);
        emit TokenCheckpoint(
            VeNFT.ActionType.INCREASE_LOCK_TIME,
            actors[actorId],
            tokenId,
            0,
            (time/WEEK)*WEEK
        );
        venft.increaseUnlockTime(tokenId, time);
    }

    function test_revertsWhen_userNotOwner() public useActor(actorId) {
        uint256 tokenId = _createLock();
        changePrank(actors[1]);
        vm.expectRevert("Unauthorized request");
        venft.increaseUnlockTime(tokenId, block.timestamp + 4 weeks);
    }

    function test_revertsWhen_reducingExistingLock() public useActor(actorId) {
        uint256 tokenId = _createLock();
        uint256 currentLock = venft.lockedEnd(tokenId);
        vm.expectRevert("Can only increase lock duration");
        venft.increaseUnlockTime(tokenId, currentLock - 1 weeks);
    }

    function test_revertsWhen_extensionGreaterThanMax() public useActor(actorId) {
        uint256 tokenId = _createLock();
        uint256 maxLock = block.timestamp + venft.MAX_TIME();
        vm.expectRevert("Voting lock can be 4 years max");
        venft.increaseUnlockTime(tokenId, maxLock + 1 weeks);
    }

    function test_revertsWhen_lockExpired() public useActor(actorId) {
        uint256 tokenId = _createLock();
        vm.warp(venft.lockedEnd(tokenId) + 1);
        vm.expectRevert("Lock expired. Withdraw");
        venft.increaseUnlockTime(tokenId, block.timestamp + 3 weeks);
    }
}

contract VeNFT_Withdraw_Test is VeNFT_Base {

    function setUp() public override {
        super.setUp();
        baseLockTime = block.timestamp + 2 weeks;
        mockToken.mint(actors[actorId], type(uint128).max);
    }
    
    function test_withdraw() public useActor(actorId){
        uint256 tokenId = _createLock();
        uint256 currentLock = venft.lockedEnd(tokenId);
        vm.warp(currentLock);
        uint256 initialBaseTokenSupply = mockToken.balanceOf(address(venft));
        vm.expectEmit(true, true, true, true);
        emit Withdraw(
            actors[actorId],
            tokenId,
            baseDepositAmt,
            block.timestamp
        );
        venft.withdraw(tokenId);
        uint256 updatedBaseTokenSupply = mockToken.balanceOf(address(venft));
        assertEq(updatedBaseTokenSupply, initialBaseTokenSupply - baseDepositAmt);
        assertEq(venft.balanceOf(actors[actorId]), 0);
    }

    function test_revertsWhen_userNotOwner() public useActor(actorId) {
        uint256 tokenId = _createLock();
        changePrank(actors[1]);
        vm.expectRevert("Unauthorized request");
        venft.withdraw(tokenId);
    }

    function test_revertsWhen_lockNotExpired() public useActor(actorId) {
        uint256 tokenId = _createLock();
        vm.expectRevert("Lock not expired");
        venft.withdraw(tokenId);
    }
}

contract VeNFT_ViewFunctions_Test is VeNFT_Base{
    function test_tokenData() public useActor(actorId) {
        assertEq(venft.balanceOfToken(1), 0);
        assertEq(venft.totalSupply(), 0);
        assertEq(venft.balanceOfUser(actors[actorId]), 0);

        // Create deposit
        uint256 tokenId = _createLock();

        // Load state variables for the position
        (uint256 amt, ) = venft.lockedBalances(tokenId);
        uint256 tokenEpc = venft.tokenPointEpoch(tokenId);
        (, int128 slope, uint256 ts) = venft.tokenPointHistory(tokenId, tokenEpc);
        
        assertEq(venft.tokenPointEpoch(tokenId), 1);
        assertEq(amt, baseDepositAmt);
        assertEq(venft.totalSupply(), venft.balanceOfToken(tokenId));
        assertEq(venft.lockedEnd(tokenId), baseLockTime);
        assertEq(venft.getLastTokenSlope(tokenId), slope);
        assertEq(venft.tokenPointHistoryTS(tokenId, tokenEpc), ts);
        assertEq(venft.getLastTokenSlope(2), 0);
    }

    function test_userData() public useActor(actorId){
        uint256 tokenId = _createLock();
        venft.createLock(baseDepositAmt, baseLockTime);

        changePrank(actors[secondaryActor]);
        _createLock();

        uint256 initialTotalSupply = venft.totalSupply();
        changePrank(actors[actorId]);
        uint256 initialUserBal = venft.balanceOfUser(actors[secondaryActor]);
        uint256 initialTokenBal = venft.balanceOfToken(1);
        venft.safeTransferFrom(actors[actorId], actors[secondaryActor], tokenId);
        assertEq(venft.balanceOfUser(actors[secondaryActor]), initialUserBal + initialTokenBal);
        assertEq(venft.balanceOfUser(actors[actorId]), venft.balanceOfToken(2));
        assertEq(venft.totalSupply(), initialTotalSupply);
    }

    function test_query_historicUserData() public useActor(actorId) {
        uint256 lockTime = baseLockTime + 6 weeks;
        mockToken.approve(address(venft), type(uint128).max);
        venft.createLock(baseDepositAmt, lockTime);
        uint256 tokenId = venft.tokenOfOwnerByIndex(actors[actorId], 0);

        uint256 ts1 = block.timestamp + 2 weeks;
        vm.warp(ts1);
        venft.increaseAmount(tokenId, baseDepositAmt);
        
        uint256 ts2 = ts1 + 2 weeks;
        vm.warp(block.timestamp + 2 weeks);
        venft.increaseUnlockTime(tokenId, lockTime + 10 weeks);
        venft.createLock(baseDepositAmt, lockTime);

        vm.warp(block.timestamp + 4 weeks);
        
        venft.safeTransferFrom(actors[actorId], actors[secondaryActor], tokenId);
        
        venft.checkpoint();
        venft.balanceOfToken(tokenId, ts1 + 100);
        venft.balanceOfUser(actors[actorId], ts2 + 100);
        venft.totalSupply(ts2 + 100);

    }

    function test_checkpoint() public useActor(actorId) {
        uint256 tokenId = _createLock();
        uint256 end = venft.lockedEnd(tokenId);
        vm.warp(block.timestamp + 3 weeks);
        venft.checkpoint();
        assertEq(venft.totalSupply(end),0);
    }
}

