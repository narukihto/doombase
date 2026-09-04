// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;
    
    address owner = address(0x1337);
    // ✅ عنوان افتراضي لمحاكاة محفظة البوت داخل بيئة الفحص
    address fakeBotAddress = address(0x9999); 

    function setUp() public {
        vm.startPrank(owner);
        // ✅ تم تمرير عنوان البوت هنا كمتغير داخل الـ Constructor لإصلاح خطأ (Wrong argument count)
        arbitrageContract = new BaseAtomicArbitrage(fakeBotAddress);
        vm.stopPrank();
    }

    // فحص البنية التحتية للتأكد من تعيين المالك وعنوان البوت المرخص بشكل سليم
    function test_contractDeploymentAndAuthorization() public {
        assertEq(arbitrageContract.owner(), owner);
        assertEq(arbitrageContract.botAddress(), fakeBotAddress);
    }
}
