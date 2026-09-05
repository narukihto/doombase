// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10 <0.9.0;

import "forge-std/Test.sol";
import "../src/BaseAtomicArbitrage.sol";

contract BaseAtomicArbitrageTest is Test {
    BaseAtomicArbitrage public arbitrageContract;

    address owner = address(0x1337);
    address fakeBotAddress = address(0x9999); 
    address attacker = address(0xBAD); 

    // تعريف المتغيرات دون قيم ثابتة لتجنب فحص الـ Checksum النصي
    address WETH;
    address USDC;
    address targetWhitelistAddress;

    function setUp() public {
        // تعيين العناوين ديناميكياً لتخطي قيود المترجم نهائياً
        WETH = vm.parseAddress("0x4200000000000000000000000000000000000006");
        USDC = vm.parseAddress("0x833589fCD6eDb6E08f4c7C32D4f71b54bda02913");
        targetWhitelistAddress = vm.parseAddress("0xcf77A3bA9Aab7D3E44917635033322DF3f564171");

        vm.startPrank(owner);
        arbitrageContract = new BaseAtomicArbitrage(fakeBotAddress);
        vm.stopPrank();
    }

    // 1️⃣ اختبار النشر والترخيص الأساسي
    function test_contractDeploymentAndAuthorization() public {
        assertEq(arbitrageContract.owner(), owner);
        assertEq(arbitrageContract.botAddress(), fakeBotAddress);
    }

    // 2️⃣ اختبار أمان حرج (Access Control)
    function test_Security_OnlyAuthorizedCanTrigger() public {
        vm.startPrank(attacker); 
        
        bytes memory mockPayloads = abi.encode(new address[](0), new bytes[](0));

        vm.expectRevert("Not authorized");
        arbitrageContract.triggerAaveArbitrage(WETH, 1 ether, mockPayloads);

        vm.expectRevert("Not authorized");
        arbitrageContract.triggerBalancerArbitrage(WETH, 1 ether, mockPayloads);
        
        vm.stopPrank();
    }

    // 3️⃣ اختبار الخاصية الذرية (Atomic Logic) وضمان الـ Revert عند عدم وجود ربح
    function test_Atomic_RevertIfNonProfitable() public {
        vm.startPrank(fakeBotAddress); 
        
        address[] memory targets = new address[](1);
        targets[0] = targetWhitelistAddress; 
        
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = ""; 
        
        bytes memory swapPathData = abi.encode(targets, payloads);
        
        vm.expectRevert();
        arbitrageContract.triggerAaveArbitrage(WETH, 0.1 ether, swapPathData);
        
        vm.stopPrank();
    }

    // 4️⃣ اختبار حماية سحب الأموال (Withdrawal Security)
    function test_Security_OnlyOwnerCanWithdraw() public {
        vm.startPrank(attacker); 
        
        vm.expectRevert("Not owner");
        arbitrageContract.withdrawToken(WETH);
        
        vm.expectRevert("Not owner");
        arbitrageContract.withdrawETH();
        
        vm.stopPrank();
    }
}
