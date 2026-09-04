// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

// 🏛️ واجهة Balancer Vault الأصلية الخاصة بك
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

// 👻 واجهة Aave V3 Pool المطلوبة للتحديث الجديد
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
    
    // عنوان موفر عقود Aave V3 الحقيقي على شبكة Base
    address private constant AAVE_POOL_PROVIDER = 0xe20fCB7cFff40D900c359ABb20a3A766FAd2eC16;
    address public immutable AAVE_POOL;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        // جلب عنوان الـ Pool النشط ديناميكياً من الـ Provider لجعل العقد مرناً ومقاوماً للترقيات
        AAVE_POOL = IAddressProvider(AAVE_POOL_PROVIDER).getPool();
    }

    // ────────────────────────────────────────────────────────
    // 💥 بوابات إطلاق القروض الوميضية (Triggers)
    // ────────────────────────────────────────────────────────

    // 1. بوابة Balancer الأصلية الخاصة بك
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

    // 2. بوابة Aave V3 الجديدة المقترحة في الـ Prompt
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

    // ────────────────────────────────────────────────────────
    // 🔄 دوال الاستقبال والـ Callback للـ Arbitrage الذري
    // ────────────────────────────────────────────────────────

    // 1. كولباك Balancer الأصلي الخاص بك (محتفظ بكامل منطق التداول المبتكر)
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "Untrusted lender");
        
        uint256 amountToRepay = amounts[0] + feeAmounts[0];
        
        // تنفيذ منطق التداول الذري المشترك لقفل الربحية
        _executeCoreArbitrage(tokens[0], amounts[0], userData);

        // إعادة الأموال تلقائياً لـ Balancer Vault
        tokens[0].transfer(BALANCER_VAULT, amountToRepay);
        
        // تحويل صافي الأرباح للمالك إن وجدت
        _payoutProfit(tokens[0]);
    }

    // 2. كولباك Aave V3 الجديد لربط الاقتراض الموازي وسداد الفوائد
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");
        
        uint256 amountToRepay = amount + premium;

        // تنفيذ نفس منطق التداول الذري المبتكر لضمان قفل الربحية
        _executeCoreArbitrage(IERC20(asset), amount, params);

        // عمل Approve لـ Aave Pool لتتمكن من سحب القرض + الفائدة حتمياً
        IERC20(asset).approve(AAVE_POOL, amountToRepay);

        return true;
    }

    // ────────────────────────────────────────────────────────
    // 🛠️ المنطق الداخلي المشترك (Core Execution & Routing)
    // ────────────────────────────────────────────────────────
    
    function _executeCoreArbitrage(IERC20 borrowedToken, uint256 loanAmount, bytes memory userData) internal {
        (address[] memory poolsPath, uint24[] memory poolFees) = abi.decode(userData, (address[], uint24[]));

        uint256 currentBalance = loanAmount;

        // تشغيل الـ Loop الذكي الخاص بك للتنقل بين الـ Pools
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

// واجهة مساعدة مدمجة لطلب محرك Aave Pool
interface IAddressProvider {
    function getPool() external view returns (address);
}
