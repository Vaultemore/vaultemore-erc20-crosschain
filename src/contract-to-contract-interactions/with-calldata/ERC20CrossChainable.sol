// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

// Imports for a source contract of a connext cross-chain interaction
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {ICallback} from "nxtp/core/promise/interfaces/ICallback.sol";
import {CallParams, XCallArgs} from "nxtp/core/connext/libraries/LibConnextStorage.sol";

// Imports for a target contract of a connext cross-chain interaction
//import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {IExecutor} from "nxtp/core/connext/interfaces/IExecutor.sol";
import {LibCrossDomainProperty} from "nxtp/core/connext/libraries/LibCrossDomainProperty.sol";

/**
 * @title ERC20CrossChainable
 * @notice Example contract for cross-domain calls (xcalls), playing both roles of xcall source and target
 */
contract ERC20CrossChainable is ICallback, ERC20, Ownable {

  // --- Events ---
  event MintRequested(address beneficiary, uint256 amount);
  event MintRequestCancelled(address canceller);
  event xMintInitiated(address caller, uint256 amountToMint, uint32 destinationDomain);
  event BurnRequestCancelled(address canceller);
  event xMintConfirmationInitiated(address beneficiary, uint32 destinationDomain);
  event MintConfirmed(address beneficiary, uint256 amount);
  event BurnConfirmed(address beneficiary, uint256 amount);

  event CallbackReceived(bytes32 transferId, bool success, address beneficiary);

  // --- Variables ---

  IConnextHandler public immutable connext;
  address public immutable promiseRouter;
  uint32 private immutable localDomainId;

  // The address of the Connext Executor contract
  IExecutor public executor;

  uint256 public constant totalSupplyCrossChain = 10 * 10e18;
  bool public isOriginMintChain;

  mapping(uint32 => address) public whitelistedDomainIds;

  // 2 attributes to store requested Mints on destination chain
  mapping(address => uint256) public addressToRequestedMint;
  mapping(address => uint256) public addressToRequestMintTimeout;

  // 2 attributes to store requested Burns on origin chain
  mapping(address => uint256) public addressToRequestedBurn;
  mapping(address => uint256) public addressToRequestBurnTimeout;

  uint256 public constant lockTimeout = 1 days;

  // --- Modifiers ---

  // A modifier for permissioning the callback.
  // Note: This is an important security consideration. Only the PromiseRouter (the
  //       Connext contract that executes the callback function) should be able to
  //       call the callback function.
  modifier onlyPromiseRouter () {
    require(
      msg.sender == address(promiseRouter),
      "Expected PromiseRouter"
    );
    _;
  }

  // A modifier for authenticated function calls.
  // Note: This is an important security consideration. It must check
  //       that the originating call is from a correct whitelisted domain and contract.
  //       Also, it must be coming from the Connext Executor address.
  modifier onlyExecutor() {
    uint32 originDomain = LibCrossDomainProperty.origin(msg.data);
    address originContract = LibCrossDomainProperty.originSender(msg.data);
    require(
      originDomain != 0 &&
      originDomain != localDomainId &&
      originContract != address(0) &&
      whitelistedDomainIds[originDomain] == originContract &&
      msg.sender == address(executor),
      "Expected origin contract and origin domain called by Executor"
    );
    _;
  }

  // --- Constructor ---

  constructor(IConnextHandler _connext, address _promiseRouter, bool _isOriginMintChain, uint32 _localDomainId, string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol, 18) {
    connext = _connext;
    promiseRouter = _promiseRouter;
    executor = _connext.executor();
    localDomainId = _localDomainId;
    
    isOriginMintChain = _isOriginMintChain;
    // Mint the totalSupplyCrossChain only if we are on the origin Mint Chain
    if (isOriginMintChain) {
      super._mint(address(this),totalSupplyCrossChain);
    }
  }

  // --- Functions ---

  /**
   * Function allowing only contract Owner to add a new domain Id and its crosschainable ERC20 contract address.
   */
  function addDomainToWhiteList(uint32 _domainId, address _contractAddress) external onlyOwner {
    require(_domainId != 0,'domainId=0');
    require(_domainId != localDomainId,'cannot modify local Domain Id');
    require(_contractAddress != address(this),'address=0');

    whitelistedDomainIds[_domainId] = _contractAddress;

  }

  /**
   * Function allowing only contract Owner to remove a domain Id and its crosschainable ERC20 contract address.
   */
  function removeFromWhiteList(uint32 _domainId) external onlyOwner {
    require(_domainId != 0,'domainId=0');
    require(_domainId != localDomainId,'cannot modify local Domain Id');

    delete whitelistedDomainIds[_domainId];

  }

  /**
   * Cross-domain mint of a given amount on a target contract, on a target chain.
   @dev Initiates the Connext bridging flow with calldata to be used on the target contract.
   */
  function xChainMint(
    uint32 _destinationDomain,
    uint256 _amountToMint,
    bool _forceSlow
  ) external payable {

    require(_destinationDomain != 0, 'dest domain = 0');
    require(_destinationDomain != localDomainId, 'dest domain = origin domain');
    require(whitelistedDomainIds[_destinationDomain] != address(0),'dest contract not allowed');
    require(_amountToMint != 0,'amount = 0');
    require(_amountToMint <= totalSupplyCrossChain,'amount > total supply cross chain');
    require(_amountToMint <= this.balanceOf(msg.sender),'amount > user balance');

    bytes4 selector;

    // Encode function of the target contract
    selector = bytes4(keccak256("initiateMint(uint256,address)"));
    bytes memory callData = abi.encodeWithSelector(selector, _amountToMint, msg.sender);

    CallParams memory callParams = CallParams({
      to: whitelistedDomainIds[_destinationDomain],
      callData: callData,
      originDomain: localDomainId,
      destinationDomain: _destinationDomain,
      agent: msg.sender, // address allowed to execute transaction on destination side in addition to relayers
      recovery: msg.sender, // fallback address to send funds to if execution fails on destination side
      forceSlow: _forceSlow, // option to force slow path instead of paying 0.05% fee on fast liquidity transfers
      receiveLocal: false, // option to receive the local bridge-flavored asset instead of the adopted asset
      callback: address(this), // this contract implements the callback
      callbackFee: 0, // fee paid to relayers for the callback; no fees on testnet
      relayerFee: 0, // fee paid to relayers for the forward call; no fees on testnet
      destinationMinOut: 0 // not sending funds so minimum can be 0
    });

    XCallArgs memory xcallArgs = XCallArgs({
      params: callParams,
      transactingAsset: address(0), // 0 address is the native gas token
      transactingAmount: 0, // not sending funds with this calldata-only xcall
      originMinOut: 0 // not sending funds so minimum can be 0
    });

    // Lock the funds temporarily
    balanceOf[msg.sender] -= _amountToMint;
    balanceOf[address(this)] += _amountToMint;
    addressToRequestedBurn[msg.sender] = _amountToMint;
    addressToRequestBurnTimeout[msg.sender] = block.timestamp + lockTimeout;

    connext.xcall(xcallArgs);

    emit xMintInitiated(msg.sender, _amountToMint, _destinationDomain);
  }

  /**
   * Callback function required for contracts implementing the ICallback interface.
   @dev This function is called to handle return data from the destination domain.
   @dev success is true if execution worked on the destination chain, false if it reverts
   */ 
  function callback(
    bytes32 transferId,
    bool success,
    bytes memory data
  ) external onlyPromiseRouter {

    (address beneficiary, uint32 originDomain) = abi.decode(data, (address, uint32));
    require(whitelistedDomainIds[originDomain] != address(0), 'chain not allowed');
    emit CallbackReceived(transferId, success, beneficiary);
    
    uint256 amount = addressToRequestedBurn[msg.sender];

    //each time that callback is called, we should always have a requested burn amount for beneficiary
    assert(amount != 0);

    if (!success) {
      // in that case, cancel the burn
      _cancelBurnRequest(beneficiary,amount);
    }
    else {
      //call the mint confirmation
      _xChainMintConfirmation(originDomain,beneficiary);
      //burn the locked tokens
      _burn(address(this),amount);
      addressToRequestedBurn[msg.sender] = 0;
      addressToRequestBurnTimeout[msg.sender] = 0;
      emit BurnConfirmed(beneficiary,amount);
    }
  }

  /**
   * Cross-domain mint confirmation call on a target contract, on a target chain.
   @dev Initiates the Connext bridging flow with calldata to be used on the target contract.
   */
  function _xChainMintConfirmation(
    uint32 _destinationDomain,
    address beneficiary
  ) internal {

    // Encode function of the target contract
    bytes4 selector = bytes4(keccak256("confirmMint(address)"));
    bytes memory callData = abi.encodeWithSelector(selector, beneficiary);

    CallParams memory callParams = CallParams({
      to: whitelistedDomainIds[_destinationDomain],
      callData: callData,
      originDomain: localDomainId,
      destinationDomain: _destinationDomain,
      agent: msg.sender, // address allowed to execute transaction on destination side in addition to relayers
      recovery: msg.sender, // fallback address to send funds to if execution fails on destination side
      forceSlow: true, // option to force slow path instead of paying 0.05% fee on fast liquidity transfers
      receiveLocal: false, // option to receive the local bridge-flavored asset instead of the adopted asset
      callback: address(0), // this contract implements the callback
      callbackFee: 0, // fee paid to relayers for the callback; no fees on testnet
      relayerFee: 0, // fee paid to relayers for the forward call; no fees on testnet
      destinationMinOut: 0 // not sending funds so minimum can be 0
    });

    XCallArgs memory xcallArgs = XCallArgs({
      params: callParams,
      transactingAsset: address(0), // 0 address is the native gas token
      transactingAmount: 0, // not sending funds with this calldata-only xcall
      originMinOut: 0 // not sending funds so minimum can be 0
    });

    connext.xcall(xcallArgs);

    emit xMintConfirmationInitiated(beneficiary, _destinationDomain);
  }

  /**
   * Function to call on target chain.
   @dev This function initiates a mint, reverts if already a pending mint request for that address
   */ 
  function initiateMint(uint256 amount, address _beneficiary) 
    external onlyExecutor returns (address, uint32)
  {

    require(addressToRequestedMint[_beneficiary] == 0, 'already a pending mint request for that address');
    
    addressToRequestedMint[_beneficiary] = amount;
    addressToRequestMintTimeout[_beneficiary] = block.timestamp + lockTimeout;
    
    emit MintRequested(_beneficiary, amount);

    return (_beneficiary, localDomainId);

  }

  /**
   * Function to call on target chain.
   @dev This function confirms a mint
   */ 
  function confirmMint(address _beneficiary) 
    external onlyExecutor
  {

    uint256 amountToMint = addressToRequestedMint[_beneficiary];

    require(amountToMint != 0, 'no pending mint request for that address');
    
    _mint(address(this),amountToMint);
    addressToRequestedMint[_beneficiary] = 0;
    addressToRequestMintTimeout[_beneficiary] = 0;
    
    emit MintConfirmed(_beneficiary, amountToMint);
  }

  /**
   * Function to cancel a request by a beneficiary on the destination chain, available lockTimeout secs after the request was initiated
   @dev It unlocks the local chain for a new xmint by msg.sender
   */ 
  function cancelMintRequest() external
  {
    require(addressToRequestedMint[msg.sender] != 0, 'no pending mint request');
    require(block.timestamp > addressToRequestMintTimeout[msg.sender], 'need to wait lockTimeout after request published');
    
    addressToRequestedMint[msg.sender] = 0;
    addressToRequestMintTimeout[msg.sender] = 0;

    emit MintRequestCancelled(msg.sender);
  }

  /**
   * Function to cancel a request by a beneficiary on the origin chain, available lockTimeout secs after the request was initiated
   @dev It unlocks the local chain for a new xmint by msg.sender
   */ 
  function cancelBurnRequest() external
  {

    uint256 amount = addressToRequestedBurn[msg.sender];

    require(amount != 0, 'no pending burn request');
    require(block.timestamp > addressToRequestBurnTimeout[msg.sender], 'need to wait lockTimeout after request published');
    
    _cancelBurnRequest(msg.sender,amount);
    
  }

  function _cancelBurnRequest(address beneficiary, uint256 amount) internal {
    // Unlock the funds
    balanceOf[beneficiary] += amount;
    balanceOf[address(this)] -= amount;

    addressToRequestedBurn[beneficiary] = 0;
    addressToRequestBurnTimeout[beneficiary] = 0;

    emit BurnRequestCancelled(beneficiary);
  }

  // EXCLUSIVE FOR TESTNET:
  mapping(address=>uint256) private lastFaucetDate;
  /**
   * EXCLUSIVE FOR TESTNET
   * Function to request token to make tests
   @dev returns 1 token to msg.sender
   */ 
  function faucet() external {

    require(lastFaucetDate[msg.sender] == 0 || lastFaucetDate[msg.sender] > block.timestamp + lockTimeout, 'need to wait before next faucet');
    require(balanceOf[address(this)] > 10e18, 'no more token available :(');

    this.transfer(msg.sender,10e17);
    lastFaucetDate[msg.sender] = block.timestamp;
  }


}
