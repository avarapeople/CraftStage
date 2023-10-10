pragma solidity >=0.8.19;

import { ISablierV2Lockup } from "@sablier/v2-core/interfaces/ISablierV2Lockup.sol";
import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";
import { IPool } from "@aave/v3-core/contracts/interfaces/IPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

error LinearStreamReceiver__InvalidAddress();

/// @title A contract which receives stream of payment from Streaming protocol(Sablier) and periodically deposits the streamed token to AAVE for yield
/// @author Parth Patel
/// @notice This contract currently receives DAI but can be made generic for any tokens
contract LinearStreamReceiver is Ownable {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //address of DAI in ETH chain
    IPool public constant POOL = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); //address of Pool in ETH chain
    ISablierV2Lockup public immutable sablier;
    address public dedicatedMsgSender; //this address will be corresponding to gelato bot. visit for more info https://docs.gelato.network/developer-services/automate/guides/dedicated-msg.sender

    event WithdrawFromStream(uint256 indexed streamId, address indexed to, uint256 amount);
    event WithdrawMaxFromStream(uint256 indexed streamId, address indexed to);
    event SupplyToAave(uint256 amount);
    event WithdrawFromAave(address indexed to, uint256 amount);

    modifier onlyDedicatedMsgSender() {
        require(msg.sender == dedicatedMsgSender, "Only dedicated msg.sender");
        _;
    }

    constructor(ISablierV2Lockup sablier_, address dedicatedMsgSender_) {
        if (address(sablier_) == address(0) || dedicatedMsgSender_ == address(0)) {
            revert LinearStreamReceiver__InvalidAddress();
        }
        sablier = sablier_;
        dedicatedMsgSender = dedicatedMsgSender_;
    }

    /// @notice withdraws the DAI token from the stream and send it to the owner defined param(to)
    /// @dev This is supposed to be called only by owner of the contract
    /// @param streamId id of stream created for this contract
    /// @param to receiver of the streamed token
    /// @param amount amount to fetch from stream
    function withdraw(uint256 streamId, address to, uint128 amount) external onlyOwner {
        if (to == address(0)) {
            revert LinearStreamReceiver__InvalidAddress();
        }
        sablier.withdraw({ streamId: streamId, to: to, amount: amount });
        emit WithdrawFromStream(streamId, to, amount);
    }

    /// @notice withdraws all the DAI token from the stream and send it to the owner defined param(to)
    /// @dev This is supposed to be called only by owner of the contract
    /// @param streamId id of stream created for this contract
    /// @param to receiver of the streamed token
    function withdrawMax(uint256 streamId, address to) external onlyOwner {
        if (to == address(0)) {
            revert LinearStreamReceiver__InvalidAddress();
        }
        sablier.withdrawMax({ streamId: streamId, to: to });
        emit WithdrawMaxFromStream(streamId, to);
    }

    /// @notice withdraws the DAI token from the stream and send supplies to AAVE for generating yield
    /// @dev This is supposed to be called by gelato bots(dedicated message sender) at periodic interval configured so that stream can be used optimally
    /// @param streamId id of stream created for this contract
    function withdrawAndSupplyOnAave(uint256 streamId) external onlyDedicatedMsgSender {
        sablier.withdrawMax({ streamId: streamId, to: address(this) });
        uint256 daiBalance = DAI.balanceOf(address(this));
        DAI.approve(address(POOL), daiBalance);
        POOL.supply(address(DAI), daiBalance, address(this), 0);
        emit SupplyToAave(daiBalance);
    }

    /// @notice withdraws the DAI token from AAVE which were generating yield
    /// @dev This is supposed to be called by owner when they need the assets or doesn't want it to generate yield
    /// @param amount amount of DAI to withdraw. If this is type(uint256).max, it means withdraw all
    /// @param to address to which the DAI tokens are sent
    function withdrawFromAave(uint256 amount, address to) external onlyOwner {
        if (to == address(0)) {
            revert LinearStreamReceiver__InvalidAddress();
        }
        POOL.withdraw(address(DAI), amount, to);
        emit WithdrawFromAave(to, amount);
    }

    /// @notice updates the gelato bots address 
    /// @dev This is supposed to be called by owner
    /// @param dedicatedMsgSender_ address which has permission to call priviliged function with onlyDedicatedMsgSender modifier
    function updateDedicatedMsgSender(address dedicatedMsgSender_) external onlyOwner {
        if (dedicatedMsgSender_ == address(0)) {
            revert LinearStreamReceiver__InvalidAddress();
        }
        dedicatedMsgSender = dedicatedMsgSender_;
    }
}