// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

        uint256 exactBalanceBefore = IERC20(tokenToBorrow).balanceOf(address(this));

        bytes memory protectedData = abi.encode(address(this), exactBalanceBefore, swapPathData);
        vault.flashLoan(this, tokens, amounts, protectedData);
    }

    function triggerAaveArbitrage(
        address tokenToBorrow,
        uint256 loanAmount,
        bytes calldata swapPathData
    ) external onlyAuthorized {
        uint256 exactBalanceBefore = IERC20(tokenToBorrow).balanceOf(address(this));
        bytes memory encodedParams = abi.encode(exactBalanceBefore, swapPathData);

        IPool(AAVE_POOL).flashLoanSimple(
            address(this),
            tokenToBorrow,
            loanAmount,
            encodedParams,
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

        (address initiator, uint256 exactBalanceBefore, bytes memory realSwapPathData) = abi.decode(userData, (address, uint256, bytes));
        require(initiator == address(this), "Untrusted initiator via Balancer");

        IERC20 token = tokens[0];
        uint256 amountToRepay = amounts[0] + feeAmounts[0];

        token.approve(BALANCER_VAULT, amountToRepay);

        _executeUniversalArbitrage(realSwapPathData);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter > (exactBalanceBefore + amountToRepay), "Arbitrage unprofitable");
    }

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

        (uint256 exactBalanceBefore, bytes memory realSwapPathData) = abi.decode(params, (uint256, bytes));

        token.approve(AAVE_POOL, amountToRepay);

        _executeUniversalArbitrage(realSwapPathData);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter > (exactBalanceBefore + amountToRepay), "Arbitrage unprofitable");

        return true;
    }

    // هندسة جديدة بالكامل: البوت الخارجي يمرر مصفوفة التوكنات، الأهداف، والـ payloads لضمان دعم التحكيم متعدد العملات والمنصات دون هدر غاز
    function _executeUniversalArbitrage(bytes memory userData) internal {
        if(userData.length == 0) return; 

        // قمنا بتحديث التشفير ليشمل مصفوفة التوكنات والمبالغ لمنح الصلاحيات بدقة متناهية
        (address[] memory tokensToApprove, address[] memory targets, bytes[] memory payloads) = abi.decode(userData, (address[], address[], bytes[]));
        uint256 length = targets.length;

        for (uint256 i = 0; i < length; i++) {
            address target = targets[i];
            address token = tokensToApprove[i];
            
            require(target != address(this) && token != address(this), "Malicious target blocked");

            // إذا كان التوكن ممرراً كعنوان صفري (0x0)، فهذا يعني أن هذه الخطوة لا تحتاج لـ approve (توفير غاز هائل وحل مشكلة USDT)
            if (token != address(0)) {
                // تصفير الصلاحية أولاً ثم إعادتها لحل مشكلة USDT والتوكنات المشابهة حتمياً
                IERC20(token).approve(target, 0);
                IERC20(token).approve(target, type(uint256).max);
            }

            (bool success, bytes memory reason) = target.call(payloads[i]);
            if (!success) {
                if (reason.length == 0) revert("DEX Swap Failed");
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        IERC20(token).transfer(owner, balance);
    }

    function updateBotAddress(address _newBot) external onlyOwner {
        botAddress = _newBot;
    }
}
