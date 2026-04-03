// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ReserveManager
 * @notice Multi-asset reserve tracking with proof of reserves and ratio enforcement.
 * @dev Part of kcolbchain/stablecoin-toolkit
 */
contract ReserveManager is Ownable {
    struct ReserveAsset {
        string name;
        uint256 amount;       // in stablecoin-equivalent units (6 decimals)
        uint256 lastUpdated;
        bool active;
    }

    mapping(bytes32 => ReserveAsset) public reserves;
    bytes32[] public reserveIds;

    uint256 public totalReserves;
    uint256 public totalSupplyTracked; // updated by Minter
    uint256 public minimumRatioBps;    // e.g. 10000 = 100%, 10500 = 105%

    event ReserveUpdated(bytes32 indexed assetId, string name, uint256 amount);
    event SupplyUpdated(uint256 newSupply);
    event MinimumRatioUpdated(uint256 newRatioBps);

    error ReserveRatioTooLow(uint256 currentRatioBps, uint256 requiredRatioBps);

    constructor(uint256 _minimumRatioBps) Ownable(msg.sender) {
        minimumRatioBps = _minimumRatioBps;
    }

    function addReserveAsset(bytes32 assetId, string calldata name, uint256 amount) external onlyOwner {
        if (!reserves[assetId].active) {
            reserveIds.push(assetId);
        }
        reserves[assetId] = ReserveAsset({
            name: name,
            amount: amount,
            lastUpdated: block.timestamp,
            active: true
        });
        _recalcTotal();
        emit ReserveUpdated(assetId, name, amount);
    }

    function updateReserve(bytes32 assetId, uint256 amount) external onlyOwner {
        require(reserves[assetId].active, "Asset not active");
        reserves[assetId].amount = amount;
        reserves[assetId].lastUpdated = block.timestamp;
        _recalcTotal();
        emit ReserveUpdated(assetId, reserves[assetId].name, amount);
    }

    function updateTrackedSupply(uint256 supply) external onlyOwner {
        totalSupplyTracked = supply;
        emit SupplyUpdated(supply);
    }

    function setMinimumRatio(uint256 ratioBps) external onlyOwner {
        minimumRatioBps = ratioBps;
        emit MinimumRatioUpdated(ratioBps);
    }

    function getReserveRatioBps() public view returns (uint256) {
        if (totalSupplyTracked == 0) return type(uint256).max;
        return (totalReserves * 10000) / totalSupplyTracked;
    }

    function checkReserveRatio() external view {
        uint256 ratio = getReserveRatioBps();
        if (ratio < minimumRatioBps) {
            revert ReserveRatioTooLow(ratio, minimumRatioBps);
        }
    }

    function getReserveCount() external view returns (uint256) {
        return reserveIds.length;
    }

    function _recalcTotal() internal {
        uint256 total = 0;
        for (uint256 i = 0; i < reserveIds.length; i++) {
            if (reserves[reserveIds[i]].active) {
                total += reserves[reserveIds[i]].amount;
            }
        }
        totalReserves = total;
    }
}
