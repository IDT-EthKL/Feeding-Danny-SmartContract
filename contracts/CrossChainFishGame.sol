// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IMailbox.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IInterchainGasPaymaster.sol";

interface IERC20Reward is IERC20 {
    function mintReward(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

interface IFishGameNFT {
    function catchFish(address player, string memory species, uint256 size, uint256 rarity) external;
    function burnFish(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function getTokenId() external view returns (uint256);
}

contract CrossChainFishGame is Ownable, ReentrancyGuard {
    IERC20Reward public rewardToken;
    IFishGameNFT public fishNFT;
    IMailbox public hyperlaneMailbox;
    IInterchainGasPaymaster public igp;
    
    mapping(uint32 => bytes32) public trustedRemotes;

    uint256 public constant BASE_FISH_COST = 10 * 10**18; // 10 tokens
    uint256 public constant BASE_REWARD = 5 * 10**18; // 5 tokens

    struct GameState {
        uint256 playerScore;
        uint256 fishSize;
        uint256 lastInteractionTime;
    }

    mapping(address => GameState) public playerStates;

    event FishEaten(address indexed player, uint256 fishSize, uint256 reward);
    event PlayerGrown(address indexed player, uint256 newSize);
    event CrossChainInteraction(uint32 originChain, address player, uint256 fishId);

    constructor(
        address _rewardToken,
        address _fishNFT,
        address _hyperlaneMailbox,
        address _igp
    ) Ownable(msg.sender) {
        rewardToken = IERC20Reward(_rewardToken);
        fishNFT = IFishGameNFT(_fishNFT);
        hyperlaneMailbox = IMailbox(_hyperlaneMailbox);
        igp = IInterchainGasPaymaster(_igp);
    }

    function setTrustedRemote(uint32 _domain, bytes32 _trustedRemote) external onlyOwner {
        trustedRemotes[_domain] = _trustedRemote;
    }

    function eatFish() external nonReentrant {
        GameState storage playerState = playerStates[msg.sender];
        require(block.timestamp - playerState.lastInteractionTime >= 1 minutes, "Wait before next action");

        uint256 fishCost = BASE_FISH_COST * (playerState.fishSize + 1);
        require(rewardToken.balanceOf(msg.sender) >= fishCost, "Insufficient tokens");

        // Burn tokens for eating attempt
        rewardToken.burnFrom(msg.sender, fishCost);

        // Generate random fish size
        uint256 targetFishSize = _generateTargetFishSize(playerState.fishSize);

        if (targetFishSize <= playerState.fishSize) {
            // Successfully eat the fish
            uint256 reward = _calculateReward(targetFishSize);
            rewardToken.mintReward(msg.sender, reward);
            playerState.playerScore += reward;
            emit FishEaten(msg.sender, targetFishSize, reward);

            // Check for player growth
            if (playerState.playerScore >= playerState.fishSize * 100 * 10**18) {
                playerState.fishSize += 1;
                emit PlayerGrown(msg.sender, playerState.fishSize);
            }
        } else {
            // Failed to eat the fish, player loses some size
            if (playerState.fishSize > 1) {
                playerState.fishSize -= 1;
            }
        }

        playerState.lastInteractionTime = block.timestamp;
    }

    function crossChainEat(uint32 destinationChain, uint256 fishId) external payable nonReentrant {
        require(fishNFT.ownerOf(fishId) == msg.sender, "Not the owner of this fish");
        
        // Burn the NFT on this chain
        fishNFT.burnFish(fishId);

        // Prepare the message for the destination chain
        bytes memory message = abi.encode(msg.sender, fishId);

        // Dispatch the message
        bytes32 messageId = hyperlaneMailbox.dispatch(
            destinationChain,
            trustedRemotes[destinationChain],
            message
        );

        // Quote and pay for interchain gas
        uint256 gasAmount = 300000; // Estimate of gas needed on destination chain
        uint256 quote = igp.quoteGasPayment(destinationChain, gasAmount);
        require(msg.value >= quote, "Insufficient interchain gas payment");
        
        igp.payForGas{value: quote}(
            messageId,
            destinationChain,
            gasAmount,
            msg.sender
        );

        if (msg.value > quote) {
            // Refund excess payment
            payable(msg.sender).transfer(msg.value - quote);
        }

        emit CrossChainInteraction(destinationChain, msg.sender, fishId);
    }

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _body
    ) external payable {
        require(msg.sender == address(hyperlaneMailbox), "Only mailbox can call");
        require(_sender == trustedRemotes[_origin], "Not a trusted remote");

        (address player, uint256 fishId) = abi.decode(_body, (address, uint256));

        // Mint a new fish NFT for the player on this chain
        (string memory species, uint256 size, uint256 rarity) = _generateFishAttributes();
        fishNFT.catchFish(player, species, size, rarity);

        // Update player's game state
        GameState storage playerState = playerStates[player];
        playerState.playerScore += size * 10; // Arbitrary scoring system
        if (playerState.playerScore >= playerState.fishSize * 100 * 10**18) {
            playerState.fishSize += 1;
            emit PlayerGrown(player, playerState.fishSize);
        }

        emit CrossChainInteraction(_origin, player, fishId);
    }

    function _generateTargetFishSize(uint256 playerSize) internal view returns (uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, playerSize)));
        return (rand % (playerSize * 2)) + 1; // Fish size between 1 and 2x player size
    }

    function _calculateReward(uint256 fishSize) internal pure returns (uint256) {
        return BASE_REWARD * fishSize;
    }

    function _generateFishAttributes() internal view returns (string memory, uint256, uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)));
        
        string[5] memory speciesList = ["Tuna", "Salmon", "Trout", "Bass", "Catfish"];
        string memory species = speciesList[rand % 5];
        
        uint256 size = (rand % 100) + 1; // 1-100 cm
        uint256 rarity = (rand % 5) + 1; // 1-5 stars

        return (species, size, rarity);
    }

    // Admin function to withdraw any stuck ERC20 tokens
    function withdrawERC20(address tokenAddress, uint256 amount) external onlyOwner {
        require(IERC20(tokenAddress).transfer(owner(), amount), "Transfer failed");
    }
}