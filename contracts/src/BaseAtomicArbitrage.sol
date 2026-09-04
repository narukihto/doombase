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
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function triggerBalancerArbitrage(
        address tokenToBorrow, 
        uint256 loanAmount, 
        bytes calldata swapPathData
    ) external onlyOwner {
        IBalancerVault vault = IBalancerVault(BALANCER_VAULT);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(tokenToBorrow);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;

        vault.flashLoan(this, tokens, amounts, swapPathData);
    }

    function triggerAaveArbitrage(
        address tokenToBorrow,
        uint256 loanAmount,
        bytes calldata swapPathData
    ) external onlyOwner {
        IPool(AAVE_POOL).flashLoanSimple(
            address(this),
            tokenToBorrow,
            loanAmount,
            swapPathData,
            0
        );
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "Untrusted lender");
        uint256 amountToRepay = amounts[0] + feeAmounts[0];
        
        _executeUniversalArbitrage(userData);
        
        uint256 currentBalance = tokens[0].balanceOf(address(this));
        require(currentBalance >= amountToRepay, "Insufficient balance for Balancer loan");
        tokens[0].transfer(BALANCER_VAULT, amountToRepay);
        _payoutProfit(tokens[0]);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address /* initiator */, 
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");
        uint256 amountToRepay = amount + premium;
        
        _executeUniversalArbitrage(params);
        
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        require(currentBalance >= amountToRepay, "Insufficient balance for Aave loan");
        IERC20(asset).approve(AAVE_POOL, amountToRepay);
        return true;
    }

    // ✅ دالة تنفيذ خارقة وديناميكية تمر على أي DEX في شبكة Base غصباً عن المترجم وبأقل استهلاك غاز!
    function _executeUniversalArbitrage(bytes memory userData) internal {
        // فك تشفير مصفوفة العناوين المستهدفة (سواء كانت راوترات أو Pools مباشرة) ومصفوفة الأوامر الخام لكل خطوة
        (address[] memory targets, bytes[] memory payloads) = abi.decode(userData, (address[], bytes[]));
        
        for (uint256 i = 0; i < targets.length; i++) {
            // تنفيذ استدعاء منخفض المستوى مباشر لكل منصة بالترتيب المخطط له من البوت
            (bool success, bytes memory reason) = targets[i].call(payloads[i]);
            if (!success) {
                if (reason.length == 0) revert("DEX Swap Failed without reason");
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function _payoutProfit(IERC20 token) internal {
        uint256 profit = token.balanceOf(address(this));
        if (profit > 0) {
            token.transfer(owner, profit);
        }
    }

    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner, balance);
    }
}
