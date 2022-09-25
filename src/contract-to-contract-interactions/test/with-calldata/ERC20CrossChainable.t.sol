// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.14;

import {ERC20CrossChainable} from "../../with-calldata/ERC20CrossChainable.sol";
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {IExecutor} from "nxtp/core/connext/interfaces/IExecutor.sol";
import {LibCrossDomainProperty} from "nxtp/core/connext/libraries/LibCrossDomainProperty.sol";
import {DSTestPlus} from "../utils/DSTestPlus.sol";
import "forge-std/Test.sol";


/**
 * @title ERC20CrossChainableTestUnit
 * @notice Unit tests for ERC20CrossChainable.
 */

 
contract ERC20CrossChainableTestUnit is DSTestPlus {
  address private connext;
  address private promiseRouter;
  ERC20CrossChainable private sourceToken;
  address private target = address(1);

  event xMintInitiated(address caller, uint256 amountToMint, uint32 destinationDomain);

  function setUp() public {
    
    connext = address(1);
    promiseRouter = address(2);
    bool isOriginMintChain = true;
    uint32 localDomainId = 1735353714; //Goerli ethereum
    string memory tokenName = "MyToken";
    string memory tokenSymbol = "MTK";
    
    sourceToken = new ERC20CrossChainable(IConnextHandler(connext), promiseRouter, isOriginMintChain, localDomainId, tokenName, tokenSymbol);
    
  }

  function testXMintEmitsEvent() public {
    address userChainA = address(0xA);
    uint32 destinationDomain = 1735356532;
    bool forceSlow = false;

    vm.label(address(userChainA), "userChainA");

    uint256 amountToMint = 100;

    // Mock the xcall
    bytes memory mockxcall = abi.encodeWithSelector(
      IConnextHandler.xcall.selector
    );
    vm.mockCall(connext, mockxcall, abi.encode(1));

    // Check for an event emitted
    vm.expectEmit(true, true, true, true);
    emit xMintInitiated(msg.sender, amountToMint, destinationDomain);

    vm.prank(address(userChainA));

    sourceToken.faucet();
    sourceToken.balanceOf(address(userChainA));

    sourceToken.xChainMint(
      destinationDomain,
      amountToMint,
      forceSlow
    );
  }
}


/**
 * @title ERC20CrossChainableTestForked
 * @notice Integration tests for ERC20CrossChainable. Should be run with forked testnet (Goerli).
 */

contract ERC20CrossChainableForked is DSTestPlus {
  // Testnet Addresses
  address public connext = 	0x8F5Ce8D12A6d825F725e465ccAf239953db0d327;
  address public promiseRouter = 	0x53CffCA4C1aDfD21a9f7913A934C46469638e31F;
  address private target = address(1);

  ERC20CrossChainable private sourceToken;

  event xMintInitiated(address caller, uint256 amountToMint, uint32 destinationDomain);

  function setUp() public {
    connext = address(1);
    promiseRouter = address(2);
    bool isOriginMintChain = true;
    uint32 localDomainId = 1735353714; //Goerli ethereum
    string memory tokenName = "MyToken";
    string memory tokenSymbol = "MTK";
    sourceToken = new ERC20CrossChainable(IConnextHandler(connext), promiseRouter, isOriginMintChain, localDomainId, tokenName, tokenSymbol);

    vm.label(address(this), "TestContract");
    vm.label(connext, "Connext");
    vm.label(address(sourceToken), "ERC20 Token");
  }

  function testXMintEmitsEventFork() public {
    address userChainA = address(0xA);
    uint32 destinationDomain = 1735356532;
    bool forceSlow = false;

    vm.label(address(userChainA), "userChainA");

    uint256 amountToMint = 100;

    // Mock the xcall
    bytes memory mockxcall = abi.encodeWithSelector(
      IConnextHandler.xcall.selector
    );
    vm.mockCall(connext, mockxcall, abi.encode(1));

    // Check for an event emitted
    vm.expectEmit(true, true, true, true);
    emit xMintInitiated(msg.sender, amountToMint, destinationDomain);

    vm.prank(address(userChainA));
    sourceToken.xChainMint(
      destinationDomain,
      amountToMint,
      forceSlow
    );
  }
}

