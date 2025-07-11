// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Counter.sol";

contract TokenTest is Test {
    Token public token;
    address public owner;
    address public user1;
    address public user2;
    address public minter;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        minter = makeAddr("minter");

        token = new Token();
    }

    function test_InitialState() public {
        assertEq(token.name(), "SecureToken");
        assertEq(token.symbol(), "STK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100000 * 10 ** 18);
        assertEq(token.owner(), owner);
        assertEq(token.balanceOf(owner), 100000 * 10 ** 18);
    }

    function test_OwnerCanMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
    }

    function test_OwnerCanAuthorizeMinter() public {
        assertFalse(token.authorizedMinters(minter));
        assertFalse(token.isAuthorizedMinter(minter));

        token.authorizeMinter(minter);

        assertTrue(token.authorizedMinters(minter));
        assertTrue(token.isAuthorizedMinter(minter));
    }

    function test_OwnerCanRevokeMinter() public {
        token.authorizeMinter(minter);
        assertTrue(token.authorizedMinters(minter));

        token.revokeMinter(minter);

        assertFalse(token.authorizedMinters(minter));
        assertFalse(token.isAuthorizedMinter(minter));
    }

    function test_AuthorizedMinterCanMintSecure() public {
        token.authorizeMinter(minter);
        uint256 mintAmount = 500 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();

        vm.prank(minter);
        token.mint_secure(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
    }

    function test_OwnerCanMintSecure() public {
        uint256 mintAmount = 500 * 10 ** 18;
        uint256 initialSupply = token.totalSupply();

        token.mint_secure(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
    }

    function test_UnauthorizedCannotMintSecure() public {
        uint256 mintAmount = 500 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert("Not authorized to mint");
        token.mint_secure(user2, mintAmount);
    }

    function test_UnauthorizedCannotMint() public {
        uint256 mintAmount = 500 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert();
        token.mint(user2, mintAmount);
    }

    function test_CannotMintToZeroAddress() public {
        vm.expectRevert("Cannot mint to zero address");
        token.mint(address(0), 1000);
    }

    function test_CannotMintZeroAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        token.mint(user1, 0);
    }

    function test_CannotAuthorizeZeroAddress() public {
        vm.expectRevert("Cannot authorize zero address");
        token.authorizeMinter(address(0));
    }

    function test_OnlyOwnerCanAuthorizeMinter() public {
        vm.prank(user1);
        vm.expectRevert();
        token.authorizeMinter(minter);
    }

    function test_OnlyOwnerCanRevokeMinter() public {
        token.authorizeMinter(minter);

        vm.prank(user1);
        vm.expectRevert();
        token.revokeMinter(minter);
    }

    function test_MintSecureEmitsEvent() public {
        token.authorizeMinter(minter);
        uint256 mintAmount = 500 * 10 ** 18;

        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit Token.MintSecure(user1, mintAmount);
        token.mint_secure(user1, mintAmount);
    }

    function test_AuthorizeMinterEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Token.MinterAuthorized(minter);
        token.authorizeMinter(minter);
    }

    function test_RevokeMinterEmitsEvent() public {
        token.authorizeMinter(minter);

        vm.expectEmit(true, false, false, true);
        emit Token.MinterRevoked(minter);
        token.revokeMinter(minter);
    }

    function test_UnlimitedSupply() public {
        uint256 largeAmount = 1000000000 * 10 ** 18;

        token.mint(user1, largeAmount);
        assertEq(token.balanceOf(user1), largeAmount);

        token.mint(user2, largeAmount);
        assertEq(token.balanceOf(user2), largeAmount);

        assertEq(token.totalSupply(), 100000 * 10 ** 18 + 2 * largeAmount);
    }

    function test_ReentrancyProtection() public {
        token.authorizeMinter(minter);

        vm.prank(minter);
        token.mint_secure(user1, 1000 * 10 ** 18);

        assertEq(token.balanceOf(user1), 1000 * 10 ** 18);
    }

    function test_FuzzMintAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        uint256 initialSupply = token.totalSupply();
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), initialSupply + amount);
    }

    function test_FuzzMintSecureAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);

        token.authorizeMinter(minter);
        uint256 initialSupply = token.totalSupply();

        vm.prank(minter);
        token.mint_secure(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), initialSupply + amount);
    }
}
