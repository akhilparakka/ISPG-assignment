// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Token is ERC20, Ownable, ReentrancyGuard {
    mapping(address => bool) public authorizedMinters;

    event MintSecure(address indexed to, uint256 amount);
    event MinterAuthorized(address indexed minter);
    event MinterRevoked(address indexed minter);

    modifier onlyAuthorizedMinter() {
        require(
            authorizedMinters[msg.sender] || msg.sender == owner(),
            "Not authorized to mint"
        );
        _;
    }

    modifier validMintParams(address to, uint256 amount) {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    constructor() ERC20("SecureToken", "STK") Ownable(msg.sender) {
        _mint(msg.sender, 100000 * 10 ** 18);
    }

    function _mintTokens(
        address to,
        uint256 amount
    ) internal validMintParams(to, amount) {
        _mint(to, amount);
    }

    function mint_secure(
        address to,
        uint256 amount
    ) external nonReentrant onlyAuthorizedMinter {
        // Call internal mint function
        _mintTokens(to, amount);

        emit MintSecure(to, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mintTokens(to, amount);
    }

    function authorizeMinter(address minter) external onlyOwner {
        require(minter != address(0), "Cannot authorize zero address");
        authorizedMinters[minter] = true;
        emit MinterAuthorized(minter);
    }

    function revokeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
        emit MinterRevoked(minter);
    }

    function isAuthorizedMinter(address minter) external view returns (bool) {
        return authorizedMinters[minter] || minter == owner();
    }
}
