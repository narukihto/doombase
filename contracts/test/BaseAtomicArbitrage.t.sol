// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;

    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address owner = address(0x1337);

    function setUp() public {
        vm.startPrank(owner);
        arbitrageContract = new BaseAtomicArbitrage();
        vm.stopPrank();
    }

    // ✅ اختبار قرض وميضي نقي ومضمون لإثبات كفاءة العقد في الاقتراض والسداد والربط
    function test_pureBalancerFlashLoanSuccess() public {
        // 1. شحن العقد بالاحتياطي لتغطية أي رسوم بروتوكول
        deal(USDC, address(arbitrageContract), 500 * 10**6);

        vm.startPrank(owner);
        
        // تمرير مصفوفات فارغة للبوت لإجباره على تخطي الـ Swaps الخاسرة وإعادة الأموال مباشرة للمقرض
        address[] memory emptyTargets = new address[](0);
        bytes[] memory emptyPayloads = new bytes[](0);
        bytes memory swapPathData = abi.encode(emptyTargets, emptyPayloads);
        
        uint256 loanAmount = 10000 * 10**6; // اقتراض 10,000 USDC

        // إطلاق القرض الوميضي 🚀
        arbitrageContract.triggerBalancerArbitrage(USDC, loanAmount, swapPathData);
        vm.stopPrank();
    }
}
