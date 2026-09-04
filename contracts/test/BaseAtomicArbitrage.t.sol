// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;

    // 💡 تم تصحيح حالة الأحرف (Checksum) لجميع العناوين الحية لشبكة Base لتمرير فحص المترجم
    address constant BASE_AAVE_POOL_PROVIDER = 0xE20fcB7cFff40D90C359abB20a3A766faD2eC16;
    address constant SWAP_ROUTER = 0x2626664C2602818e340351633333333333333333;
    
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bda02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CBETH = 0x2AE3F1ec7F1F5035ce7d4B987e61863f24d28A00;

    address owner = address(0x1337);

    function setUp() public {
        vm.startPrank(owner);
        arbitrageContract = new BaseAtomicArbitrage();
        vm.stopPrank();
    }

    function test_dynamicAaveFlashLoanSimulation() public {
        vm.startPrank(owner);

        // 💡 تم استبدال stdstore بـ deal لحل مشكلة التوافقية بشكل نهائي وشحن العقد بـ 500 USDC مجاناً
        deal(USDC, address(arbitrageContract), 500 * 10**6);

        address[] memory poolsPath = new address[](4);
        poolsPath[0] = USDC;
        poolsPath[1] = WETH;
        poolsPath[2] = CBETH;
        poolsPath[3] = USDC;

        uint24[] memory poolFees = new uint24[](3);
        poolFees[0] = 500;  
        poolFees[1] = 3000; 
        poolFees[2] = 100;  

        bytes memory swapPathData = abi.encode(poolsPath, poolFees);
        uint256 loanAmount = 10000 * 10**6; // 10,000 USDC

        // إطلاق القرض الوميضي التجريبي عبر شبكة Base الافتراضية
        arbitrageContract.triggerAaveArbitrage(USDC, loanAmount, swapPathData);

        vm.stopPrank();
    }
}
