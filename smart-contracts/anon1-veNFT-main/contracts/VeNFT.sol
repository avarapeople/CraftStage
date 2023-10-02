// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721, ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/// @title Voting Escrow Template
/// @dev src: https://github.com/Sperax/Vote-Escrow-Smart-Contract-Template/blob/main/contracts/veToken.sol
/// @notice This is an extension and Solidity implementation of the CURVE's voting escrow.
/// @notice Votes have a weight depending on time, so that users are
///         committed to the future of (whatever they are voting for)
/// @dev Vote weight decays linearly over time. Lock time cannot be
///  more than `MAX_TIME` (4 years).

/**
# Voting escrow to have time-weighted votes
# w ^
# 1 +        /
#   |      /
#   |    /
#   |  /
#   |/
# 0 +--------+------> time
#       maxtime (4 years?)
*/

contract VeNFT is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    Ownable,
    ReentrancyGuard
{
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    enum ActionType {
        DEPOSIT_FOR,
        CREATE_LOCK,
        INCREASE_AMOUNT,
        INCREASE_LOCK_TIME
    }

    struct Point {
        int256 bias; // veToken value at this point
        int128 slope; // slope at this point
        uint256 ts; // timestamp of this point
    }

    struct UserData {
        uint256 ts;
        uint256[] tokenIds;
    }

    struct LockedBalance {
        uint128 amount; // amount of Token locked for a user.
        uint256 end; // the expiry time of the deposit.
    }

    uint256 public constant WEEK = 1 weeks;
    uint256 public constant MAX_TIME = 4 * 365 days;
    uint256 public constant MULTIPLIER = 10 ** 18;
    int128 public constant I_YEAR = int128(uint128(365 days));

    address public immutable baseToken;
    uint256 public totalTokenLocked;
    Counters.Counter private _tokenIds;
    /// Base Token related information

    /// @dev Mappings to store global point information
    uint256 public epoch;
    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(uint256 => int128) public slopeChanges; // time -> signed slope change

    /// @dev Mappings to store token deposit information
    mapping(uint256 => LockedBalance) public lockedBalances; // user Deposits
    mapping(uint256 => mapping(uint256 => Point)) public tokenPointHistory; // tokenId -> point[userEpoch]
    mapping(uint256 => uint256) public tokenPointEpoch;

    /// @dev Mappings to store historical user token data
    mapping(address => mapping(uint256 => UserData)) public userTokenHistory;
    mapping(address => uint256) public userEpoch;

    event TokenCheckpoint(
        ActionType indexed actionType,
        address indexed user,
        uint256 indexed tokenId,
        uint256 value,
        uint256 locktime
    );
    event GlobalCheckpoint(address caller, uint256 epoch);
    event Withdraw(
        address indexed user,
        uint256 indexed tokenId,
        uint256 value,
        uint256 ts
    );
    event Supply(uint256 prevSupply, uint256 supply);
    event UserPositionsMerged(
        address indexed user,
        uint256 primaryTokenId,
        uint256 secondaryTokenId
    );

    /// @dev Constructor
    constructor(address _token) ERC721("vote-escrowed NFT", "VeNFT") {
        require(_token != address(0), "_token is zero address");
        baseToken = _token;
        pointHistory[0].ts = block.timestamp;
    }

    /// @notice Record global data to checkpoint
    function checkpoint() external {
        _updateGlobalPoint();
        emit GlobalCheckpoint(_msgSender(), epoch);
    }

    /// @notice Deposit and lock tokens for a user
    /// @param addr Address of the desired user
    /// @dev Anyone (even a smart contract) can deposit tokens for someone else, but
    ///      cannot extend their locktime and deposit for a user that is not locked
    /// @param tokenId Id of the desired token
    /// @param value Amount of tokens to deposit
    function depositFor(
        address addr,
        uint256 tokenId,
        uint128 value
    ) external nonReentrant {
        require(_ownerOf(tokenId) == addr, "Invalid request");
        LockedBalance memory existingDeposit = lockedBalances[tokenId];
        require(value > 0, "Cannot deposit 0 tokens");

        require(
            existingDeposit.end > block.timestamp,
            "Lock expired. Withdraw"
        );
        _depositFor(
            addr,
            tokenId,
            value,
            0,
            existingDeposit,
            ActionType.DEPOSIT_FOR
        );
    }

    /// @notice Deposit `value` for `msg.sender` and lock untill `unlockTime`
    /// @param value Amount of tokens to deposit
    /// @param unlockTime Time when the tokens will be unlocked
    /// @dev unlockTime is rownded down to whole weeks
    function createLock(
        uint128 value,
        uint256 unlockTime
    ) external nonReentrant {
        address account = msg.sender;
        uint256 roundedUnlockTime = (unlockTime / WEEK) * WEEK;
        uint256 tokenId = _mintNextToken(account);
        LockedBalance memory existingDeposit = lockedBalances[tokenId];

        require(value > 0, "Cannot lock 0 tokens");
        require(roundedUnlockTime > block.timestamp, "Cannot lock in the past");
        require(
            roundedUnlockTime <= block.timestamp + MAX_TIME,
            "Voting lock can be 4 years max"
        );
        _depositFor(
            account,
            tokenId,
            value,
            roundedUnlockTime,
            existingDeposit,
            ActionType.CREATE_LOCK
        );
    }

    /// @notice Deposit `value` additional tokens for `tokenId` without
    ///         modifying the locktime
    /// @param tokenId Id of the desired token
    /// @param value Amount of tokens to deposit
    function increaseAmount(
        uint256 tokenId,
        uint128 value
    ) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender, "Unauthorized request");
        LockedBalance memory existingDeposit = lockedBalances[tokenId];

        require(value > 0, "Cannot deposit 0 tokens");

        require(
            existingDeposit.end > block.timestamp,
            "Lock expired. Withdraw"
        );
        _depositFor(
            msg.sender,
            tokenId,
            value,
            0,
            existingDeposit,
            ActionType.INCREASE_AMOUNT
        );
    }

    /// @notice Extend the locktime of `tokenId` tokens to `unlockTime`
    /// @param tokenId Id of the desired token
    /// @param unlockTime New locktime
    function increaseUnlockTime(uint256 tokenId, uint256 unlockTime) external {
        require(_ownerOf(tokenId) == msg.sender, "Unauthorized request");
        LockedBalance memory existingDeposit = lockedBalances[tokenId];
        uint256 roundedUnlockTime = (unlockTime / WEEK) * WEEK; // Locktime is rounded down to weeks

        require(
            existingDeposit.end > block.timestamp,
            "Lock expired. Withdraw"
        );
        require(
            roundedUnlockTime > existingDeposit.end,
            "Can only increase lock duration"
        );
        require(
            roundedUnlockTime <= block.timestamp + MAX_TIME,
            "Voting lock can be 4 years max"
        );

        _depositFor(
            msg.sender,
            tokenId,
            0,
            roundedUnlockTime,
            existingDeposit,
            ActionType.INCREASE_LOCK_TIME
        );
    }

    /// @notice Withdraw tokens for `msg.sender`
    /// @dev Only possible if the locktime has expired
    /// @param tokenId Id of the desired token
    function withdraw(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender, "Unauthorized request");
        LockedBalance memory existingDeposit = lockedBalances[tokenId];
        require(block.timestamp >= existingDeposit.end, "Lock not expired");
        uint128 value = existingDeposit.amount;

        LockedBalance memory oldDeposit = lockedBalances[tokenId];
        lockedBalances[tokenId] = LockedBalance(0, 0);
        uint256 prevSupply = totalTokenLocked;
        totalTokenLocked -= value;

        // oldDeposit can have either expired <= timestamp or 0 end
        // existingDeposit has 0 end
        // Both can have >= 0 amount
        _checkpoint(tokenId, oldDeposit, LockedBalance(0, 0));

        // Transfer the underlying base token back to the user.
        IERC20(baseToken).safeTransfer(msg.sender, value);

        // Burn the nft token for the user
        _burn(tokenId);

        emit Withdraw(msg.sender, tokenId, value, block.timestamp);
        emit Supply(prevSupply, totalTokenLocked);
    }

    /// @notice Merge multiple NFT positions for user
    /// @param primaryId Primary position Id
    /// @param secondaryId Secondary position Id
    function mergePositions(uint256 primaryId, uint256 secondaryId) external {
        // Check if it is an authorized operation.
        require(_ownerOf(primaryId) == msg.sender, "Unauthorized request");
        require(_ownerOf(secondaryId) == msg.sender, "Unauthorized request");

        // Fetch existing position data
        LockedBalance memory primaryLock = lockedBalances[primaryId];
        LockedBalance memory secondaryLock = lockedBalances[secondaryId];

        // Ensure that none of the positions are expired
        require(block.timestamp < primaryLock.end, "Lock expired");
        require(block.timestamp < secondaryLock.end, "Lock expired");

        // Calculate the new unlock time
        // @dev new UnlockTime = max(primaryLock.end, secondaryLock.end)
        uint256 newUnlockTime = primaryLock.end >= secondaryLock.end
            ? primaryLock.end
            : secondaryLock.end;

        // Create new deposit data object
        LockedBalance memory updatedPrimaryLock = LockedBalance({
            amount: (primaryLock.amount + secondaryLock.amount),
            end: newUnlockTime
        });
        // Update the primary lock position
        _checkpoint(primaryId, primaryLock, updatedPrimaryLock);

        // Update and purge the secondary lock position
        lockedBalances[secondaryId] = LockedBalance(0, 0);
        _checkpoint(secondaryId, secondaryLock, LockedBalance(0, 0));
        _burn(secondaryId);

        emit UserPositionsMerged(msg.sender, primaryId, secondaryId);
    }

    /// @notice Splits an existing user position
    /// @param tokenId Id of the desired token
    /// @param splitAmount Amount to be locked in the new token
    // function splitPositions(uint256 tokenId, uint256 splitAmount) external {
    //     revert("To be implemented");
    // }

    /// @notice Get the most recently recorded rate of voting power decrease for `addr`
    /// @param tokenId Id of the desired token
    /// @return value of the slope
    function getLastTokenSlope(uint256 tokenId) external view returns (int128) {
        uint256 tEpoch = tokenPointEpoch[tokenId];
        if (tEpoch == 0) {
            return 0;
        }
        return tokenPointHistory[tokenId][tEpoch].slope;
    }

    /// @notice Get the timestamp for checkpoint `idx` for `tokenId`
    /// @param tokenId Id of the desired token
    /// @param idx User epoch number
    /// @return Epoch time of the checkpoint
    function tokenPointHistoryTS(
        uint256 tokenId,
        uint256 idx
    ) external view returns (uint256) {
        return tokenPointHistory[tokenId][idx].ts;
    }

    /// @notice Get timestamp when `tokenId`'s lock finishes
    /// @param tokenId Id of the desired token
    /// @return Timestamp when lock finishes
    function lockedEnd(uint256 tokenId) external view returns (uint256) {
        return lockedBalances[tokenId].end;
    }

    /// @notice Get the current voting power a `tokenId` at current time
    /// @param tokenId UniqueId for the token
    /// @return Voting power associated with a token at current time
    function balanceOfToken(uint256 tokenId) external view returns (uint256) {
        return balanceOfToken(tokenId, block.timestamp);
    }

    /// @notice Get the voting power for a user at the specified timestamp
    /// @dev Adheres to ERC20 `balanceOf` interface for Aragon compatibility
    /// @param tokenId uniqueId of the token
    /// @param ts Timestamp to get voting power at
    /// @return Voting power of user at timestamp
    function balanceOfToken(
        uint256 tokenId,
        uint256 ts
    ) public view returns (uint256) {
        uint256 _epoch = _findTokenTimestampEpoch(tokenId, ts);
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = tokenPointHistory[tokenId][_epoch];
            lastPoint.bias -=
                lastPoint.slope *
                int128(int256(ts) - int256(lastPoint.ts));
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint256(lastPoint.bias);
        }
    }

    /// @notice Gets the current voting power of a user
    /// @param  addr Address of the user
    /// @return Voting power of user at current timestamp
    function balanceOfUser(address addr) public view returns (uint256) {
        return balanceOfUser(addr, block.timestamp);
    }

    /// @notice Gets the voting power of a user at a given time
    /// @param addr Address of the user
    /// @return Voting power of user at timestamp `ts`
    function balanceOfUser(
        address addr,
        uint256 ts
    ) public view returns (uint256) {
        uint256 epc = _findUserTimestampEpoch(addr, ts);
        if (epc == 0) {
            return 0;
        } else {
            UserData memory lastPoint = userTokenHistory[addr][epc];
            uint256 bal = 0;
            for (uint256 i = 0; i < lastPoint.tokenIds.length; ++i) {
                bal += balanceOfToken(lastPoint.tokenIds[i], ts);
            }
            return bal;
        }
    }

    /// @notice Calculate total voting power at current timestamp
    /// @return Total voting power at current timestamp
    function totalSupply()
        public
        view
        override(ERC721Enumerable)
        returns (uint256)
    {
        return totalSupply(block.timestamp);
    }

    /// @notice Calculate total voting power at a given timestamp
    /// @return Total voting power at timestamp
    function totalSupply(uint256 ts) public view returns (uint256) {
        uint256 _epoch = _findGlobalTimestampEpoch(ts);
        Point memory lastPoint = pointHistory[_epoch];
        return supplyAt(lastPoint, ts);
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Pre-Transfer Hook
    /// @dev Handles the accounting of positions for a user
    ///      Required to account for user's historical balance.
    /// @inheritdoc ERC721
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        if (from != address(0)) {
            _checkpointUserPositions(from, tokenId, false);
        }
        if (to != address(0)) {
            _checkpointUserPositions(to, tokenId, true);
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /// @notice Mints next token Id
    /// @param to address
    function _mintNextToken(address to) internal returns (uint256 tokenId) {
        _tokenIds.increment();
        tokenId = _tokenIds.current();
        _safeMint(to, tokenId);
    }

    /// @notice Calculate total voting power at some point in the past
    /// @param point The point (bias/slope) to start search from
    /// @param ts Timestamp to calculate total voting power at
    /// @return Total voting power at timestamp
    function supplyAt(
        Point memory point,
        uint256 ts
    ) internal view returns (uint256) {
        Point memory lastPoint = point;
        uint256 ti = (lastPoint.ts / WEEK) * WEEK;

        // Calculate the missing checkpoints
        for (uint256 i = 0; i < 255; i++) {
            ti += WEEK;
            int128 dSlope = 0;
            if (ti > ts) {
                ti = ts;
            } else {
                // check for scheduled slope changes for the week
                dSlope = slopeChanges[ti];
            }
            lastPoint.bias -=
                lastPoint.slope *
                int128(int256(ti) - int256(lastPoint.ts));
            if (ti == ts) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.ts = ti;
        }

        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(lastPoint.bias);
    }

    /// @notice Get the nearest known token epoch for a given timestamp
    /// @param tokenId tokenId
    /// @param ts desired timestamp
    function _findTokenTimestampEpoch(
        uint256 tokenId,
        uint256 ts
    ) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = tokenPointEpoch[tokenId];

        for (uint256 i = 0; i < 128; i++) {
            if (min >= max) {
                break;
            }
            uint256 mid = (min + max + 1) / 2;
            if (tokenPointHistory[tokenId][mid].ts <= ts) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /// @notice Get the nearest known user epoch for a given timestamp
    /// @param addr User's address
    /// @param ts desired timestamp
    function _findUserTimestampEpoch(
        address addr,
        uint256 ts
    ) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = userEpoch[addr];

        for (uint256 i = 0; i < 128; i++) {
            if (min >= max) {
                break;
            }
            uint256 mid = (min + max + 1) / 2;
            if (userTokenHistory[addr][mid].ts <= ts) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /// @notice Get the nearest known Global epoch for a given timestamp
    /// @param ts desired timestamp
    function _findGlobalTimestampEpoch(
        uint256 ts
    ) internal view returns (uint256) {
        uint256 min = 0;
        uint256 max = epoch;

        for (uint256 i = 0; i < 128; i++) {
            if (min >= max) {
                break;
            }
            uint256 mid = (min + max + 1) / 2;
            if (pointHistory[mid].ts <= ts) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /// @notice checkpoint user positions
    /// @dev Function assits in calculating historical votes for a given user
    /// @param addr Address of the user
    /// @param tokenId TokenId added or removed from the user
    /// @param isIncoming Flag determining id to be added or removed
    function _checkpointUserPositions(
        address addr,
        uint256 tokenId,
        bool isIncoming
    ) private {
        uint256 currentEpoch = userEpoch[addr];
        uint256 nextEpoch = currentEpoch + 1;
        uint256[] memory tokens = userTokenHistory[addr][currentEpoch].tokenIds;
        uint256[] storage updatedTokenIds = userTokenHistory[addr][nextEpoch]
            .tokenIds;
        if (isIncoming) {
            // Handle addition of new token for user
            for (uint8 i = 0; i < tokens.length; ++i) {
                updatedTokenIds.push(tokens[i]);
            }
            updatedTokenIds.push(tokenId);
        } else {
            // Handle removal of new token for user
            for (uint8 i = 0; i < tokens.length; ++i) {
                if (tokens[i] != tokenId) {
                    updatedTokenIds.push(tokens[i]);
                }
            }
        }
        // Update user's data points
        userTokenHistory[addr][nextEpoch].ts = block.timestamp;
        userEpoch[addr] = nextEpoch;
    }

    /// @notice Deposit and lock tokens for a user
    /// @param addr Address of the token owner
    /// @param tokenId Deposit token Id
    /// @param value Amount of tokens to deposit
    /// @param unlockTime Time when the tokens will be unlocked
    /// @param oldDeposit Previous locked balance of the user / timestamp
    function _depositFor(
        address addr,
        uint256 tokenId,
        uint128 value,
        uint256 unlockTime,
        LockedBalance memory oldDeposit,
        ActionType _type
    ) private {
        LockedBalance memory newDeposit = lockedBalances[tokenId];
        uint256 prevSupply = totalTokenLocked;

        totalTokenLocked += value;
        // Adding to existing lock, or if a lock is expired - creating a new one
        newDeposit.amount += value;
        if (unlockTime != 0) {
            newDeposit.end = unlockTime;
        }
        lockedBalances[tokenId] = newDeposit;

        _checkpoint(tokenId, oldDeposit, newDeposit);

        if (value != 0) {
            IERC20(baseToken).safeTransferFrom(
                msg.sender,
                address(this),
                value
            );
        }

        emit TokenCheckpoint(_type, addr, tokenId, value, newDeposit.end);
        emit Supply(prevSupply, totalTokenLocked);
    }

    /// @notice Record global and per-user data to checkpoint
    /// @param tokenId Unique deposit token Id.
    /// @param oldDeposit Previous locked balance / end lock time for the user
    /// @param newDeposit New locked balance / end lock time for the user
    function _checkpoint(
        uint256 tokenId,
        LockedBalance memory oldDeposit,
        LockedBalance memory newDeposit
    ) private {
        Point memory uOld = Point(0, 0, 0);
        Point memory uNew = Point(0, 0, 0);
        int128 dSlopeOld = 0;
        int128 dSlopeNew = 0;
        // Calculate slopes and biases for oldDeposit
        // Skipped in case of createLock
        if (oldDeposit.amount > 0) {
            int128 amt = int128(oldDeposit.amount);
            if (oldDeposit.end > block.timestamp) {
                uOld.slope = amt / I_YEAR;

                uOld.bias =
                    uOld.slope *
                    (int256(oldDeposit.end) - int256(block.timestamp));
            }
        }
        // Calculate slopes and biases for newDeposit
        // Skipped in case of withdraw
        if ((newDeposit.end > block.timestamp) && (newDeposit.amount > 0)) {
            int128 amt = int128(newDeposit.amount);
            if (newDeposit.end > block.timestamp) {
                uNew.slope = amt / I_YEAR;
                uNew.bias =
                    uNew.slope *
                    (int256(newDeposit.end) - int256(block.timestamp));
            }
        }
        // Read values of scheduled changes in the slope
        // oldDeposit.end can be in the past and in the future
        // newDeposit.end can ONLY be in the future, unless everything expired: than zeros
        dSlopeOld = slopeChanges[oldDeposit.end];
        if (newDeposit.end != 0) {
            // if not "withdraw"
            dSlopeNew = slopeChanges[newDeposit.end];
        }

        // add all global checkpoints from last added global check point until now
        Point memory lastPoint = _updateGlobalPoint();
        // If last point was in this block, the slope change has been applied already
        // But in such case we have 0 slope(s)

        // update the last global checkpoint (now) with user action's consequences
        lastPoint.slope += (uNew.slope - uOld.slope);
        lastPoint.bias += (uNew.bias - uOld.bias);
        if (lastPoint.slope < 0) {
            // it will never happen if everything works correctly
            lastPoint.slope = 0;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        pointHistory[epoch] = lastPoint; // Record the changed point into the global history by replacement

        // Schedule the slope changes (slope is going down)
        // We subtract new_user_slope from [new_locked.end]
        // and add old_user_slope to [old_locked.end]
        if (oldDeposit.end > block.timestamp) {
            // old_dslope was <something> - u_old.slope, so we cancel that
            dSlopeOld += uOld.slope;
            if (newDeposit.end == oldDeposit.end) {
                // It was a new deposit, not extension
                dSlopeOld -= uNew.slope;
            }
            slopeChanges[oldDeposit.end] = dSlopeOld;
        }

        if (newDeposit.end > block.timestamp) {
            if (newDeposit.end > oldDeposit.end) {
                dSlopeNew -= uNew.slope;
                // old slope disappeared at this point
                slopeChanges[newDeposit.end] = dSlopeNew;
            }
            // else: we recorded it already in old_dslopes̄
        }
        // Now handle user history
        uint256 userEpc = tokenPointEpoch[tokenId] + 1;
        tokenPointEpoch[tokenId] = userEpc;
        uNew.ts = block.timestamp;
        tokenPointHistory[tokenId][userEpc] = uNew;
    }

    /// @notice add checkpoints to pointHistory for every week from last added checkpoint until now
    /// @dev pointHistory include all weekly global checkpoints and some additional in-week global checkpoints
    /// @return lastPoint by calling this function
    function _updateGlobalPoint() private returns (Point memory lastPoint) {
        uint256 _epoch = epoch;
        lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp});
        Point memory initialLastPoint = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp
        });
        if (_epoch > 0) {
            lastPoint = pointHistory[_epoch];
            initialLastPoint = pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;

        // If last point is already recorded in this block, blockSlope is zero
        // But that's ok b/c we know the block in such case.
        // Go over weeks to fill history and calculate what the current point is
        {
            uint256 ti = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; i++) {
                // Hopefully it won't happen that this won't get used in 4 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                ti += WEEK;
                int128 dslope = 0;
                if (ti > block.timestamp) {
                    ti = block.timestamp;
                } else {
                    dslope = slopeChanges[ti];
                }
                // calculate the slope and bias of the new last point
                lastPoint.bias -=
                    lastPoint.slope *
                    int128(int256(ti) - int256(lastCheckpoint));
                lastPoint.slope += dslope;
                // check sanity
                if (lastPoint.bias < 0) {
                    lastPoint.bias = 0;
                }
                if (lastPoint.slope < 0) {
                    lastPoint.slope = 0;
                }

                lastCheckpoint = ti;
                lastPoint.ts = ti;
                _epoch += 1;
                if (ti == block.timestamp) {
                    pointHistory[_epoch] = lastPoint;
                    break;
                }
                pointHistory[_epoch] = lastPoint;
            }
        }
        epoch = _epoch;
        return lastPoint;
    }
}
