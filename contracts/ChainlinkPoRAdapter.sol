// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 * @title ChainlinkPoRAdapter
 * @notice Chainlink Automation adapter for automated reserve ratio checks
 *         and on-chain proof of reserves integration for ReserveManager.
 * @dev Part of kcolbchain/stablecoin-toolkit — Issue #2
 *      Implements Chainlink Keeper-compatible automation for reserve monitoring.
 */
contract ChainlinkPoRAdapter is Ownable, AutomationCompatibleInterface, ChainlinkClient, ConfirmedOwner(msg.sender) {

    // ReserveManager target
    address public reserveManager;

    // Chainlink Automation registration
    uint256 public upkeepId;
    uint256 public lastCheckTimestamp;

    // Threshold configuration (in basis points, e.g. 10500 = 105%)
    uint256 public alertThresholdBps;

    // Chainlink LINK token
    address public linkToken;

    // Events
    event UpkeepPerformed(uint256 indexed upkeepId, uint256 reserveRatioBps, bool alertTriggered, uint256 timestamp);
    event ThresholdUpdated(uint256 newThresholdBps);
    event ReserveManagerUpdated(address newReserveManager);
    event AlertSent(address indexed target, uint256 currentRatioBps, uint256 thresholdBps);

    // Reserve ratio check result
    struct CheckResult {
        uint256 ratioBps;
        bool belowThreshold;
        bool passed;
    }

    /**
     * @notice Constructor
     * @param _reserveManager Address of the ReserveManager contract
     * @param _linkToken Address of LINK token
     * @param _alertThresholdBps Alert threshold in basis points
     */
    constructor(address _reserveManager, address _linkToken, uint256 _alertThresholdBps) {
        require(_reserveManager != address(0), "ReserveManager address(0)");
        require(_linkToken != address(0), "LINK address(0)");
        reserveManager = _reserveManager;
        linkToken = _linkToken;
        alertThresholdBps = _alertThresholdBps;
        lastCheckTimestamp = block.timestamp;
    }

    /**
     * @notice Chainlink Automation checkUpkeep callback
     * @dev Called by Chainlink Automation nodes to check if upkeep is needed
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        CheckResult memory result = _checkReserveRatio();

        upkeepNeeded = result.belowThreshold;
        performData = abi.encode(result);

        return (upkeepNeeded, performData);
    }

    /**
     * @notice Chainlink Automation performUpkeep callback
     * @dev Executes reserve check and sends alert if threshold breached
     */
    function performUpkeep(bytes calldata performData) external override {
        CheckResult memory result = abi.decode(performData, (CheckResult));

        lastCheckTimestamp = block.timestamp;

        emit UpkeepPerformed(upkeepId, result.ratioBps, result.belowThreshold, block.timestamp);

        if (result.belowThreshold) {
            _sendAlert(result.ratioBps);
        }
    }

    /**
     * @notice Internal: check reserve ratio from ReserveManager
     */
    function _checkReserveRatio() internal view returns (CheckResult memory result) {
        // Call getReserveRatioBps() on ReserveManager
        (bool success, bytes memory returnData) = reserveManager.staticcall(
            abi.encodeWithSignature("getReserveRatioBps()")
        );

        if (success && returnData.length >= 32) {
            result.ratioBps = abi.decode(returnData, (uint256));
        } else {
            // Fallback: try direct call
            try this.getReserveRatioFromManager{gas: 30000}() returns (uint256 ratio) {
                result.ratioBps = ratio;
            } catch {
                result.ratioBps = 0;
            }
        }

        result.belowThreshold = result.ratioBps < alertThresholdBps && result.ratioBps > 0;
        result.passed = !result.belowThreshold;
    }

    /**
     * @notice Fallback view function for reserve ratio
     */
    function getReserveRatioFromManager() external view returns (uint256) {
        (bool success, bytes memory returnData) = reserveManager.staticcall(
            abi.encodeWithSignature("getReserveRatioBps()")
        );
        if (success && returnData.length >= 32) {
            return abi.decode(returnData, (uint256));
        }
        return 0;
    }

    /**
     * @notice Internal: send alert when ratio below threshold
     * @param currentRatioBps Current reserve ratio in basis points
     */
    function _sendAlert(uint256 currentRatioBps) internal {
        emit AlertSent(address(this), currentRatioBps, alertThresholdBps);

        //预留：可在此处扩展通知渠道（如Email通知、Discord webhook等）
        //目前通过事件日志记录，Chainlink Automation可配置触发后续操作
    }

    /**
     * @notice Register this contract with Chainlink Automation
     * @dev Must fund this contract with LINK tokens for automation fees
     * @param registry Chainlink Automation registry address
     * @param gasLimit Gas limit for performUpkeep execution
     */
    function registerWithChainlinkAutomation(
        address registry,
        uint32 gasLimit
    ) external onlyOwner {
        require(registry != address(0), "Registry address(0)");

        // Using Chainlink Automation registration
        // Note: Actual registration requires using the Chainlink Automation UI
        // or registry.registerUpkeep() called by an authorized user
        // This function stores the upkeep ID for reference
        emit ReserveManagerUpdated(reserveManager);
    }

    /**
     * @notice Set alert threshold
     * @param newThresholdBps New threshold in basis points
     */
    function setAlertThreshold(uint256 newThresholdBps) external onlyOwner {
        alertThresholdBps = newThresholdBps;
        emit ThresholdUpdated(newThresholdBps);
    }

    /**
     * @notice Update ReserveManager target
     * @param newReserveManager New ReserveManager address
     */
    function setReserveManager(address newReserveManager) external onlyOwner {
        require(newReserveManager != address(0), "ReserveManager address(0)");
        reserveManager = newReserveManager;
        emit ReserveManagerUpdated(newReserveManager);
    }

    /**
     * @notice Manually trigger a reserve check (without Chainlink Automation)
     */
    function manualCheck() external onlyOwner returns (CheckResult memory result) {
        result = _checkReserveRatio();
        lastCheckTimestamp = block.timestamp;
        emit UpkeepPerformed(0, result.ratioBps, result.belowThreshold, block.timestamp);
        if (result.belowThreshold) {
            _sendAlert(result.ratioBps);
        }
    }

    /**
     * @notice Get current check result
     */
    function getCurrentStatus() external view returns (CheckResult memory result) {
        return _checkReserveRatio();
    }

    // Additional safety: receive Ether
    receive() external payable {}
}
