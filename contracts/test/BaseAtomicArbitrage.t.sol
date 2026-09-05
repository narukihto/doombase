// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;

    address owner = address(0x1337);
    address fakeBotAddress = address(0x9999); 

    function setUp() public {
        vm.startPrank(owner);
        // تمرير المتغيرات بشكل سليم لإصلاح خطأ النشر داخل الفحص
        arbitrageContract = new BaseAtomicArbitrage(fakeBotAddress);
        vm.stopPrank();
    }

    // ✅ تمت إزالة 'view' لحل تعارض بيئة الفحص والمترجم بشكل نهائي
    function test_contractDeploymentAndAuthorization() public {
        assertEq(arbitrageContract.owner(), owner);
        assertEq(arbitrageContract.botAddress(), fakeBotAddress);
    }
}
