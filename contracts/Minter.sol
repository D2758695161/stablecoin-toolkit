// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Stablecoin.sol";
import "./ReserveManager.sol";
import "./ComplianceModule.sol";

/**
 * @title Minter
 * @notice Minting/redemption gateway with compliance and reserve checks.
 * @dev Part of kcolbchain/stablecoin-toolkit
 */
contract Minter is Ownable {
    Stablecoin public stablecoin;
    ReserveManager public reserveManager;
    ComplianceModule public compliance;

    uint256 public mintFeeBps;    // e.g. 10 = 0.1%
    uint256 public redeemFeeBps;
    address public feeCollector;

    mapping(address => bool) public authorizedMinters;

    struct Redemption {
        address redeemer;
        uint256 amount;
        uint256 fee;
        uint256 timestamp;
        bool settled;
    }

    Redemption[] public redemptions;

    event Minted(address indexed to, uint256 amount, uint256 fee);
    event RedemptionQueued(uint256 indexed id, address indexed redeemer, uint256 amount);
    event RedemptionSettled(uint256 indexed id);
    event MinterAuthorized(address indexed minter);
    event MinterRevoked(address indexed minter);

    error NotAuthorizedMinter();
    error ReserveCheckFailed();
    error AlreadySettled();

    modifier onlyAuthorizedMinter() {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) {
            revert NotAuthorizedMinter();
        }
        _;
    }

    constructor(
        address _stablecoin,
        address _reserveManager,
        address _compliance,
        uint256 _mintFeeBps,
        uint256 _redeemFeeBps,
        address _feeCollector
    ) Ownable(msg.sender) {
        stablecoin = Stablecoin(_stablecoin);
        reserveManager = ReserveManager(_reserveManager);
        compliance = ComplianceModule(_compliance);
        mintFeeBps = _mintFeeBps;
        redeemFeeBps = _redeemFeeBps;
        feeCollector = _feeCollector;
    }

    function authorizeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = true;
        emit MinterAuthorized(minter);
    }

    function revokeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
        emit MinterRevoked(minter);
    }

    function mint(address to, uint256 amount) external onlyAuthorizedMinter {
        // Check compliance
        compliance.checkCompliance(to, amount);

        // Check reserves can support new supply
        uint256 newSupply = stablecoin.totalSupply() + amount;
        reserveManager.updateTrackedSupply(newSupply);
        reserveManager.checkReserveRatio();

        // Calculate fee
        uint256 fee = (amount * mintFeeBps) / 10000;
        uint256 netAmount = amount - fee;

        // Mint
        stablecoin.mint(to, netAmount);
        if (fee > 0) {
            stablecoin.mint(feeCollector, fee);
        }

        // Record daily spend for compliance
        compliance.recordSpend(to, amount);

        emit Minted(to, netAmount, fee);
    }

    function redeem(uint256 amount) external {
        // Check compliance
        compliance.checkCompliance(msg.sender, amount);

        uint256 fee = (amount * redeemFeeBps) / 10000;

        // Burn tokens
        stablecoin.burnFrom(msg.sender, amount);

        // Update tracked supply
        reserveManager.updateTrackedSupply(stablecoin.totalSupply());

        // Queue redemption for settlement
        redemptions.push(Redemption({
            redeemer: msg.sender,
            amount: amount - fee,
            fee: fee,
            timestamp: block.timestamp,
            settled: false
        }));

        emit RedemptionQueued(redemptions.length - 1, msg.sender, amount - fee);
    }

    function settleRedemption(uint256 id) external onlyOwner {
        if (redemptions[id].settled) revert AlreadySettled();
        redemptions[id].settled = true;
        emit RedemptionSettled(id);
    }

    function setFees(uint256 _mintFeeBps, uint256 _redeemFeeBps) external onlyOwner {
        mintFeeBps = _mintFeeBps;
        redeemFeeBps = _redeemFeeBps;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function getRedemptionCount() external view returns (uint256) {
        return redemptions.length;
    }
}
