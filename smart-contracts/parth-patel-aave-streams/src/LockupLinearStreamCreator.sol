pragma solidity >=0.8.19;

import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear } from "@sablier/v2-core/types/DataTypes.sol";
import { ud60x18 } from "@sablier/v2-core/types/Math.sol";
import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";

error LockupLinearStreamCreator__InvalidAddress();


/// @notice Example of creating a Lockup Linear stream.
/// @dev This code is referenced from the docs: https://docs.sablier.com/contracts/v2/guides/create-stream/lockup-linear
contract LockupLinearStreamCreator {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //address of DAI in ETH chain
    ISablierV2LockupLinear public immutable lockupLinear;

    event StreamCreate(uint256 indexed streamId, address indexed recipient, uint256 totalAmount);

    constructor(ISablierV2LockupLinear lockupLinear_) {
        if (address(lockupLinear_) == address(0)) {
            revert LockupLinearStreamCreator__InvalidAddress();
        }
        lockupLinear = lockupLinear_;
    }

    /// @notice creates the stream of DAI tokens
    /// @param recipient receiver of the streamed tokens
    /// @param totalAmount total amount of DAI tokens to stream
    /// @param cliff time after which assets will be unlocked
    /// @param totalTime total duration of stream
    function createLockupLinearStream(address recipient, uint128 totalAmount, uint40 cliff, uint40 totalTime) public returns (uint256 streamId) {
        // Transfer the provided amount of DAI tokens to this contract
        DAI.transferFrom(msg.sender, address(this), totalAmount);

        // Approve the Sablier contract to spend DAI
        DAI.approve(address(lockupLinear), totalAmount);

        // Declare the params struct
        LockupLinear.CreateWithDurations memory params;

        // Declare the function parameters
        params.sender = msg.sender; // The sender will be able to cancel the stream
        params.recipient = recipient; // The recipient of the streamed assets
        params.totalAmount = uint128(totalAmount); // Total amount is the amount inclusive of all fees
        params.asset = DAI; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.durations = LockupLinear.Durations({
            cliff: cliff, // Assets will be unlocked only after cliff
            total: totalTime // Total duration
         });
        params.broker = Broker(address(0), ud60x18(0)); // Optional parameter for charging a fee

        // Create the Sablier stream using a function that sets the start time to `block.timestamp`
        streamId = lockupLinear.createWithDurations(params);

        emit StreamCreate(streamId, recipient, totalAmount);
    }
}