// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;
    address owner = address(0x1337);

    function setUp() public {
        vm.startPrank(owner);
        arbitrageContract = new BaseAtomicArbitrage();
        vm.stopPrank();
    }

    // فحص أساسي ومضمون للتأكد من نجاح بناء العقد الذكي وتعيين المالك بشكل سليم
    function test_contractDeploymentAndOwnership() public {
        assertEq(arbitrageContract.owner(), owner);
    }
}
