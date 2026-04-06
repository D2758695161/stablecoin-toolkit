// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ChainlinkPoRAdapter.sol";

contract MockRM {
    uint256 public reserveRatioBps;
    function setReserveRatioBps(uint256 r) external { reserveRatioBps = r; }
    function getReserveRatioBps() external view returns (uint256) { return reserveRatioBps; }
}

contract MockLINK {
    function transfer(address, uint256) external pure returns (bool) { return true; }
}

contract ChainlinkPoRAdapterTest is Test {
    ChainlinkPoRAdapter public adapter;
    MockRM public mockRM;
    function setUp() public {
        mockRM = new MockRM();
        adapter = new ChainlinkPoRAdapter(address(mockRM), address(new MockLINK()), 10500);
    }
    function test_aboveThreshold() public { mockRM.setReserveRatioBps(12000); (,bool below,) = abi.decode(adapter.getCurrentStatus(), (uint256,bool,bool)); assertFalse(below); }
    function test_belowThreshold() public { mockRM.setReserveRatioBps(10000); (,bool below,) = abi.decode(adapter.getCurrentStatus(), (uint256,bool,bool)); assertTrue(below); }
    function test_checkUpkeep_needed() public { mockRM.setReserveRatioBps(10000); (bool needed,) = adapter.checkUpkeep(""); assertTrue(needed); }
}