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

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
}

contract BaseAtomicArbitrage is IFlashLoanRecipient {
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant SWAP_ROUTER = 0x2626664c2602818e340351633333333333333333; 

    // ✅ تم ربط عنوان الـ Pool المباشر لـ Aave V3 على شبكة Base لتفادي فشل الـ Provider في الـ Fork
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
        _executeCoreArbitrage(amounts[0], userData);
        tokens[0].transfer(BALANCER_VAULT, amountToRepay);
        _payoutProfit(tokens[0]);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address /* initiator */, // 💡 تم التعليق لإلغاء تحذير المترجم
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");

        uint256 amountToRepay = amount + premium;
        _executeCoreArbitrage(amount, params);
        IERC20(asset).approve(AAVE_POOL, amountToRepay);
        return true;
    }

    function _executeCoreArbitrage(uint256 loanAmount, bytes memory userData) internal {
        (address[] memory poolsPath, uint24[] memory poolFees) = abi.decode(userData, (address[], uint24[]));
        uint256 currentBalance = loanAmount;

        for (uint256 i = 0; i < poolsPath.length - 1; i++) {
            IERC20(poolsPath[i]).approve(SWAP_ROUTER, currentBalance);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: poolsPath[i],
                tokenOut: poolsPath[i + 1],
                fee: poolFees[i],
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: currentBalance,
                amountOutMinimum: 1, 
                sqrtPriceLimitX96: 0
            });

            currentBalance = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
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
