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

        // نقوم بدمج (Encode) عنوان العقد كبصمة تحقق حاسمة لحماية دالة الاستقبال
        bytes memory protectedData = abi.encode(address(this), swapPathData);

        vault.flashLoan(this, tokens, amounts, protectedData);
    }

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

    // استقبال وتنفيذ قرض Balancer - مغلق تماماً ضد الاختراق وموفر للغاز
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "Untrusted lender");

        // فك تشفير بصمة الأمان ومسار الصفقات الأصلي
        (address initiator, bytes memory realSwapPathData) = abi.decode(userData, (address, bytes));
        // حماية حاسمة: حظر الهجوم الخارجي إذا حاول شخص استدعاء عقدك عبر Balancer
        require(initiator == address(this), "Untrusted initiator via Balancer");

        IERC20 token = tokens[0];
        uint256 amountToRepay = amounts[0] + feeAmounts[0];
        uint256 balanceBefore = token.balanceOf(address(this)) - amounts[0];

        _executeUniversalArbitrage(realSwapPathData);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= amountToRepay, "Arbitrage unprofitable");

        token.transfer(BALANCER_VAULT, amountToRepay);

        uint256 finalBalance = token.balanceOf(address(this));
        if (finalBalance > balanceBefore) {
            emit ArbitrageSuccess(finalBalance - balanceBefore);
        }
    }

    // استقبال وتنفيذ قرض Aave - آمن تماماً
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator, 
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");
        require(initiator == address(this), "Untrusted initiator");

        IERC20 token = IERC20(asset);
        uint256 amountToRepay = amount + premium;
        uint256 balanceBefore = token.balanceOf(address(this)) - amount;

        _executeUniversalArbitrage(params);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= amountToRepay, "Arbitrage unprofitable");

        token.approve(AAVE_POOL, amountToRepay);

        uint256 finalBalance = token.balanceOf(address(this));
        if (finalBalance > balanceBefore) {
            emit ArbitrageSuccess(finalBalance - balanceBefore);
        }

        return true;
    }

    function _executeUniversalArbitrage(bytes memory userData) internal {
        if(userData.length == 0) return; 

        (address[] memory targets, bytes[] memory payloads) = abi.decode(userData, (address[], bytes[]));
        uint256 length = targets.length;

        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory reason) = targets[i].call(payloads[i]);
            if (!success) {
                if (reason.length == 0) revert("DEX Swap Failed without reason");
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

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
