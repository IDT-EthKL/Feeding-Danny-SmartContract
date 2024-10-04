// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IMessageRecipient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ERC20Reward is ERC20Pausable, IMessageRecipient, Ownable, ERC20Burnable {
    address public hyperlaneMailbox;
    mapping(uint32 => bytes32) public trustedRemotes;

    uint256 public constant MAX_SUPPLY = 1000000 * 10**18; // 1 million tokens
    uint256 public constant DAILY_REWARD_LIMIT = 1000 * 10**18; // 1000 tokens

    mapping(address => bool) public gameMasters;
    mapping(address => uint256) public lastRewardTime;
    uint256 private _tokenIdCounter;

    event RewardMinted(address indexed player, uint256 amount);
    event GameMasterAdded(address indexed gameMaster);
    event GameMasterRemoved(address indexed gameMaster);

    constructor(address _hyperlaneMailbox) ERC20("Bilis", "BLS") Ownable(msg.sender) {
        hyperlaneMailbox = _hyperlaneMailbox;
        gameMasters[msg.sender] = true;
    }

    modifier onlyGameMaster() {
        require(gameMasters[msg.sender], "Caller is not a game master");
        _;
    }

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _body
    ) external payable override whenNotPaused {
        require(msg.sender == hyperlaneMailbox, "Caller must be the mailbox");
        require(_sender == trustedRemotes[_origin], "Sender must be trusted remote");

        (address player, uint256 amount) = abi.decode(_body, (address, uint256));
        _mintReward(player, amount);
    }

    function setTrustedRemote(uint32 _domain, bytes32 _trustedRemote) external onlyOwner {
        trustedRemotes[_domain] = _trustedRemote;
    }

    function setMailbox(address _mailbox) external onlyOwner {
        hyperlaneMailbox = _mailbox;
    }

    function addGameMaster(address _gameMaster) external onlyOwner {
        gameMasters[_gameMaster] = true;
        emit GameMasterAdded(_gameMaster);
    }

    function removeGameMaster(address _gameMaster) external onlyOwner {
        gameMasters[_gameMaster] = false;
        emit GameMasterRemoved(_gameMaster);
    }

    function mintReward(address _player, uint256 _amount) external onlyGameMaster whenNotPaused {
        _mintReward(_player, _amount);
    }

    function _mintReward(address _player, uint256 _amount) internal {
        require(totalSupply() + _amount <= MAX_SUPPLY, "Max supply reached");
        require(block.timestamp - lastRewardTime[_player] >= 1 days, "Daily reward limit reached");
        require(_amount <= DAILY_REWARD_LIMIT, "Reward exceeds daily limit");

        _mint(_player, _amount);
        lastRewardTime[_player] = block.timestamp;
        emit RewardMinted(_player, _amount);
    }

    function getTokenId() external returns (uint256) {
        _tokenIdCounter += 1;
        return _tokenIdCounter;
    }

    // Override _update to resolve the inheritance conflict
    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }

    // Override required functions
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}