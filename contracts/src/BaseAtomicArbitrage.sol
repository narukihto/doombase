// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract BaseAtomicArbitrage is IFlashLoanRecipient {
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    
    // تصحيح نسق الأحرف للعنوان بناءً على متطلبات المترجم لمنع الخطأ
    address private constant SWAP_ROUTER = 0x2626664c2602818e340351633333333333333333; 
    
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function triggerArbitrage(
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

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "Untrusted lender");

        IERC20 borrowedToken = tokens[0];
        uint256 loanAmount = amounts[0];
        uint256 fee = feeAmounts[0];
        uint256 amountToRepay = loanAmount + fee;

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

        uint256 finalBalance = borrowedToken.balanceOf(address(this));
        
        // التحقق الحتمي من ربحية المعاملة الذرية بالكامل قبل الحفظ
        require(finalBalance >= amountToRepay, "Arbitrage unprofitable, collapsing transaction!");

        borrowedToken.transfer(BALANCER_VAULT, amountToRepay);

        uint256 profit = borrowedToken.balanceOf(address(this));
        if (profit > 0) {
            borrowedToken.transfer(owner, profit);
        }
    }

    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner, balance);
    }
}
