// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;

    // 🏛️ العناوين الثابتة والحقيقية على شبكة Base Mainnet لـ Aave و Uniswap والعملات
    address constant BASE_AAVE_POOL_PROVIDER = 0xe20fCB7cFff40D900c359ABb20a3A766FAd2eC16;
    address constant SWAP_ROUTER = 0x2626664c2602818e340351633333333333333333;
    
    // عناوين العملات الحقيقية للفحص الديناميكي
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bda02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CBETH = 0x2Ae3F1Ec7F1F5035CE7d4B987e61863F24D28A00;

    address owner = address(0x1337);

    function setUp() public {
        // تنفيذ النشر محاكاةً باسم المالك
        vm.startPrank(owner);
        arbitrageContract = new BaseAtomicArbitrage();
        vm.stopPrank();
    }

    function test_dynamicAaveFlashLoanSimulation() public {
        vm.startPrank(owner);

        // 1️⃣ شحن العقد افتراضياً (بدون فلوس حقيقية) لتغطية الفوائد (Premium) التي يطلبها Aave
        // قمنا بضخ 500 USDC داخل العقد على نسخة الفورك لتأمين السداد التلقائي بنجاح
        stdstore
            .target(USDC)
            .sig("balanceOf(address)")
            .with_key(address(arbitrageContract))
            .checked_write(500 * 10**6);

        // 2️⃣ بناء مسار تداول ديناميكي مبتكر لاختبار دالة الـ Loop (مسار يتكون من 3 عملات لتبادل متعدد)
        // المسار: USDC -> WETH -> cbETH -> USDC
        address[] memory poolsPath = new address[](4);
        poolsPath[0] = USDC;
        poolsPath[1] = WETH;
        poolsPath[2] = CBETH;
        poolsPath[3] = USDC;

        // تحديد رسوم الـ Pools المقابلة لكل عملية تبديل (مثال: 0.05% لـ USDC/WETH)
        uint24[] memory poolFees = new uint24[](3);
        poolFees[0] = 500;  
        poolFees[1] = 3000; 
        poolFees[2] = 100;  

        // ترميز البيانات ديناميكياً بصيغة Bytes تماماً كما يتوقعها العقد والبوت
        bytes memory swapPathData = abi.encode(poolsPath, poolFees);

        // حجم القرض الوميضي الديناميكي المطلوب (مثال: اقتراض 10,000 USDC)
        uint256 loanAmount = 10000 * 10**6;

        // 3️⃣ إطلاق المعاملة: الاستدعاء سيتصل بـ Aave الحقيقي على الفورك، ويقترض، ويمرر المسار التبادلي بالكامل
        // الاختبار سينجح فقط إذا عاد القرض وقبلت Aave السداد دون Revert
        arbitrageContract.triggerAaveArbitrage(USDC, loanAmount, swapPathData);

        vm.stopPrank();
    }
}
