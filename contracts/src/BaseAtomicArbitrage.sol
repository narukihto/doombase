// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract BaseAtomicArbitrage is IFlashLoanRecipient {
    // عناوين العقود الرسمية والثابتة على شبكة Base
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address public owner;
    address public botAddress; 

    event ArbitrageSuccess(uint256 profit);

    modifier onlyAuthorized() {
        require(msg.sender == owner || msg.sender == botAddress, "Not authorized");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _botAddress) {
        owner = msg.sender;
        botAddress = _botAddress;
    }

    // إطلاق عملية التحكيم عبر قرض Balancer الوميضي
    function triggerBalancerArbitrage(
        address tokenToBorrow, 
        uint256 loanAmount, 
        bytes calldata swapPathData
    ) external onlyAuthorized {
        IBalancerVault vault = IBalancerVault(BALANCER_VAULT);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(tokenToBorrow);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;

        vault.flashLoan(this, tokens, amounts, swapPathData);
    }

    // إطلاق عملية التحكيم عبر قرض Aave الوميضي
    function triggerAaveArbitrage(
        address tokenToBorrow,
        uint256 loanAmount,
        bytes calldata swapPathData
    ) external onlyAuthorized {
        IPool(AAVE_POOL).flashLoanSimple(
            address(this),
            tokenToBorrow,
            loanAmount,
            swapPathData,
            0
        );
    }

    // 1. استقبال وتنفيذ قرض Balancer (Base Network)
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "Untrusted lender");
        
        IERC20 token = tokens[0];
        uint256 amountToRepay = amounts[0] + feeAmounts[0];
        uint256 balanceBefore = token.balanceOf(address(this)) - amounts[0];

        // تنفيذ الصفقات الديناميكية الحرة على شبكة Base
        _executeUniversalArbitrage(address(token), amounts[0], userData);

        uint256 balanceAfter = token.balanceOf(address(this));
        // شرط الربحية الصارم: التراجع التام في حال كانت الصفقة غير مربحة لحمايتك من الخسارة
        require(balanceAfter >= amountToRepay, "Arbitrage unprofitable");
        
        // إعادة أموال القرض والرسوم لـ Balancer
        token.transfer(BALANCER_VAULT, amountToRepay);

        // تجميع الأرباح داخل العقد لتوفير الغاز لسباق الـ MEV الفوري
        uint256 finalBalance = token.balanceOf(address(this));
        if (finalBalance > balanceBefore) {
            emit ArbitrageSuccess(finalBalance - balanceBefore);
        }
    }

    // 2. استقبال وتنفيذ قرض Aave (Base Network)
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address /* initiator */, 
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");
        
        IERC20 token = IERC20(asset);
        uint256 amountToRepay = amount + premium;
        uint256 balanceBefore = token.balanceOf(address(this)) - amount;

        // تنفيذ الصفقات الديناميكية الحرة على شبكة Base
        _executeUniversalArbitrage(asset, amount, params);

        uint256 balanceAfter = token.balanceOf(address(this));
        // شرط الربحية الصارم
        require(balanceAfter >= amountToRepay, "Arbitrage unprofitable");
        
        // تفويض Aave بسحب مستحقاته
        token.approve(AAVE_POOL, amountToRepay);
        
        uint256 finalBalance = token.balanceOf(address(this));
        if (finalBalance > balanceBefore) {
            emit ArbitrageSuccess(finalBalance - balanceBefore);
        }

        return true;
    }

    // دالة التنفيذ الحر والشامل لـ "كل منصات Base" بدون قيود Whitelist
    function _executeUniversalArbitrage(address initialToken, uint256 initialAmount, bytes memory userData) internal {
        if(userData.length == 0) return; 
        
        (address[] memory targets, bytes[] memory payloads) = abi.decode(userData, (address[], bytes[]));
        uint256 length = targets.length;
        
        for (uint256 i = 0; i < length; i++) {
            // منح الصلاحية التلقائية للمنصة الأولى في المسار بشكل صحيح
            if (i == 0) {
                IERC20(initialToken).approve(targets[i], initialAmount);
            }

            // استدعاء أي منصة بشكل مباشر وديناميكي يمليه البوت الخارجي
            (bool success, bytes memory reason) = targets[i].call(payloads[i]);
            if (!success) {
                if (reason.length == 0) revert("DEX Swap Failed without reason");
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    // سحب الأرباح المتراكمة في أي وقت بأمان تام بواسطة مالك العقد فقط
    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        IERC20(token).transfer(owner, balance);
    }

    function updateBotAddress(address _newBot) external onlyOwner {
        botAddress = _newBot;
    }

    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner, balance);
    }
}
