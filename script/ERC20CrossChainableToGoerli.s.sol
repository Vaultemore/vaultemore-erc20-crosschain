// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Script.sol";
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import "../src/contract-to-contract-interactions/with-calldata/ERC20CrossChainable.sol";

contract DeployERC20CrossChainableToGoerli is Script {

  IConnextHandler connext = IConnextHandler(0x8F5Ce8D12A6d825F725e465ccAf239953db0d327);
  address public promiseRouter = 	0x53CffCA4C1aDfD21a9f7913A934C46469638e31F;
  bool public isOriginMintChain = true;
  uint32 public localDomainId = 1735353714;
  string public tokenName = "Vaultemore";
  string public tokenSymbol = "VTM";

  function run() external {
    //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast();

    ERC20CrossChainable sourceToken = new ERC20CrossChainable(connext, promiseRouter, isOriginMintChain, localDomainId, tokenName, tokenSymbol);

    vm.stopBroadcast();
  }
}
