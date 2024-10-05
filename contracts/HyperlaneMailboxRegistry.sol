// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract HyperlaneMailboxRegistry {
    address public owner;
    mapping(uint32 => address) public mailboxes;

    event MailboxUpdated(uint32 indexed chainId, address mailbox);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function setMailbox(uint32 chainId, address mailbox) external onlyOwner {
        mailboxes[chainId] = mailbox;
        emit MailboxUpdated(chainId, mailbox);
    }

    function getMailbox(uint32 chainId) external view returns (address) {
        return mailboxes[chainId];
    }

    function batchSetMailboxes(uint32[] calldata chainIds, address[] calldata mailboxAddresses) external onlyOwner {
        require(chainIds.length == mailboxAddresses.length, "Arrays length mismatch");
        for (uint i = 0; i < chainIds.length; i++) {
            mailboxes[chainIds[i]] = mailboxAddresses[i];
            emit MailboxUpdated(chainIds[i], mailboxAddresses[i]);
        }
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}