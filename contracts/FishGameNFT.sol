// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@hyperlane-xyz/core/contracts/interfaces/IMessageRecipient.sol";

contract FishGameNFT is ERC721, ERC721Enumerable, ERC721Burnable, Ownable, IMessageRecipient {
    uint256 private _nextTokenId;

    struct Fish {
        string species;
        uint256 size;
        uint256 rarity;
        uint256 level;
        uint256 experience;
    }

    mapping(uint256 => Fish) public fishes;
    address public hyperlaneMailbox;
    mapping(uint32 => bytes32) public trustedRemotes;
    mapping(address => bool) public gameMasters;

    event FishCaught(uint256 indexed tokenId, address indexed player, string species, uint256 size, uint256 rarity);
    event FishLeveledUp(uint256 indexed tokenId, uint256 newLevel);
    event ExperienceAdded(uint256 indexed tokenId, uint256 amount);
    event GameMasterAdded(address indexed gameMaster);
    event GameMasterRemoved(address indexed gameMaster);

    constructor(address _hyperlaneMailbox) ERC721("FishGameNFT", "FISH") Ownable(msg.sender) {
        hyperlaneMailbox = _hyperlaneMailbox;
        gameMasters[msg.sender] = true;
    }

    modifier onlyGameMaster() {
        require(gameMasters[msg.sender], "Caller is not a game master");
        _;
    }

    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external payable override {
        require(msg.sender == hyperlaneMailbox, "Caller must be the mailbox");
        require(_sender == trustedRemotes[_origin], "Sender must be trusted remote");

        (address to, uint256 tokenId, Fish memory fish) = abi.decode(_body, (address, uint256, Fish));
        _safeMint(to, tokenId);
        fishes[tokenId] = fish;
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

    function catchFish(address player, string memory species, uint256 size, uint256 rarity) external onlyGameMaster {
        uint256 tokenId = _nextTokenId++;
        _safeMint(player, tokenId);

        Fish memory newFish = Fish({
            species: species,
            size: size,
            rarity: rarity,
            level: 1,
            experience: 0
        });

        fishes[tokenId] = newFish;
        emit FishCaught(tokenId, player, species, size, rarity);
    }

    function addExperience(uint256 tokenId, uint256 amount) external onlyGameMaster {
        require(ownerOf(tokenId) != address(0), "Fish does not exist");
        Fish storage fish = fishes[tokenId];
        fish.experience += amount;
        emit ExperienceAdded(tokenId, amount);

        // Check for level up
        uint256 newLevel = (fish.experience / 100) + 1; // Simple leveling logic: level = (experience / 100) + 1
        if (newLevel > fish.level) {
            fish.level = newLevel;
            emit FishLeveledUp(tokenId, newLevel);
        }
    }

    function getFish(uint256 tokenId) external view returns (Fish memory) {
        require(ownerOf(tokenId) != address(0), "Fish does not exist");
        return fishes[tokenId];
    }

    function getTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    // Implement burn functionality
    function burnFish(uint256 tokenId) external onlyGameMaster {
        _burn(tokenId);
        delete fishes[tokenId];
    }
}