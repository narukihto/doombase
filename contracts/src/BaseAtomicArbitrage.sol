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

interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
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

contract BaseAtomicArbitrage is IFlashLoanRecipient, IFlashLoanSimpleReceiver {
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address public owner;
    address public botAddress; 

    mapping(address => bool) public whitelistedTargets;

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

    function setTargetWhitelist(address target, bool status) external onlyOwner {
        whitelistedTargets[target] = status;
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

        bytes memory protectedData = abi.encode(msg.sender, exactBalanceBefore, tokenToBorrow, swapPathData);
        vault.flashLoan(this, tokens, amounts, protectedData);
    }

    function triggerAaveArbitrage(
        address tokenToBorrow,
        uint256 loanAmount,
        bytes calldata swapPathData
    ) external onlyAuthorized {
        uint256 exactBalanceBefore = IERC20(tokenToBorrow).balanceOf(address(this));
        bytes memory encodedParams = abi.encode(msg.sender, exactBalanceBefore, tokenToBorrow, swapPathData);

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

        (address originalInitiator, uint256 exactBalanceBefore, address tokenToBorrow, bytes memory realSwapPathData) = abi.decode(userData, (address, uint256, address, bytes));
        require(originalInitiator == owner || originalInitiator == botAddress, "Untrusted original initiator");

        IERC20 token = tokens[0];
        uint256 amountToRepay = amounts[0] + feeAmounts[0];

        _executeUniversalArbitrage(tokenToBorrow, realSwapPathData);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= (exactBalanceBefore + amountToRepay), "Arbitrage unprofitable");

        require(token.approve(BALANCER_VAULT, amountToRepay), "Balancer approve failed");
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator, 
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == AAVE_POOL, "Untrusted Aave pool");
        require(initiator == address(this), "Untrusted contract initiator");

        (address originalInitiator, uint256 exactBalanceBefore, address tokenToBorrow, bytes memory realSwapPathData) = abi.decode(params, (address, uint256, address, bytes));
        require(originalInitiator == owner || originalInitiator == botAddress, "Untrusted original initiator");

        IERC20 token = IERC20(asset);
        uint256 amountToRepay = amount + premium;

        _executeUniversalArbitrage(tokenToBorrow, realSwapPathData);

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= (exactBalanceBefore + amountToRepay), "Arbitrage unprofitable");

        require(token.approve(AAVE_POOL, amountToRepay), "Aave approve failed");

        return true;
    }

    // دالة المعالجة الاحترافية المكتوبة بلغة الـ Assembly (Yul) بالكامل لتدمير البطء وتوفير الغاز
    function _executeUniversalArbitrage(address tokenToBorrow, bytes memory userData) internal {
        if(userData.length == 0) return; 

        (address[] memory targets, bytes[] memory payloads) = abi.decode(userData, (address[], bytes[]));
        uint256 length = targets.length;

        require(length == payloads.length, "Length mismatch");

        // استخدام القائمة البيضاء المخزنة في الـ mapping عبر الـ Assembly
        bytes32 slot = clinitest_getMappingSlot(targets);

        assembly {
            let targetsOffset := add(targets, 32)
            let payloadsOffset := add(payloads, 32)

            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                // جلب عنوان المنصة المستهدفة الحالية
                let target := mload(add(targetsOffset, mul(i, 32)))
                
                // منع العقد من استدعاء نفسه
                if eq(target, address()) {
                    // Revert: Self-call blocked
                    mstore(0, 0x08c379a0) // Selector لـ Error(string)
                    mstore(32, 32)
                    mstore(64, 16)
                    mstore(96, "Self-call blocked")
                    revert(0, 128)
                }

                // الحماية من الاختراق: تحقق On-chain عبر الـ Assembly أن الهدف مسموح به في الـ Whitelist
                mstore(0, target)
                mstore(32, slot)
                let hashSlot := keccak256(0, 64)
                let isWhitelisted := sload(hashSlot)
                
                if iszero(isWhitelisted) {
                    mstore(0, 0x08c379a0)
                    mstore(32, 32)
                    mstore(64, 22)
                    mstore(96, "Target not whitelisted")
                    revert(0, 128)
                }

                // جلب الـ Payload الحالي ومؤشر البيانات الخاص به
                let payload := mload(add(payloadsOffset, mul(i, 32)))
                let payloadLength := mload(payload)
                let payloadData := add(payload, 32)

                // إذا كان الهدف هو عقد العملة المقترضة (لأجل الـ Approve)
                if eq(target, tokenToBorrow) {
                    if lt(payloadLength, 4) {
                        mstore(0, 0x08c379a0)
                        mstore(32, 32)
                        mstore(64, 21)
                        mstore(96, "Invalid token payload")
                        revert(0, 128)
                    }
                    // قراءة الـ Selector أول 4 بايت
                    let selector := and(mload(payloadData), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                    // التحقق الصارم: اسمح فقط بـ approve (0x095ea7b3) وامنع الـ Transfer نهائياً لحماية القرض
                    if iszero(eq(selector, 0x095ea7b300000000000000000000000000000000000000000000000000000000)) {
                        mstore(0, 0x08c379a0)
                        mstore(32, 32)
                        mstore(64, 29)
                        mstore(96, "Direct token transfer blocked")
                        revert(0, 128)
                    }
                }

                // تنفيذ الـ Call بسرعة فائقة وعزل الـ Return data لتفادي تلف الـ Memory
                let success := call(gas(), target, 0, payloadData, payloadLength, 0, 0)
                
                if iszero(success) {
                    // في حال فشل الـ Swap، نقوم بعمل Revert فوري وتمرير السبب لـ صوليديتي لحفظ الغاز
                    let size := returndatasize()
                    returndatacopy(0, 0, size)
                    revert(0, size)
                }
            }
        }
    }

    // دالة مساعدة داخلية لجلب موقع الـ Slot الخاص بالـ Whitelist لتسهيل قراءته في الـ Assembly
    function clinitest_getMappingSlot(address[] memory) internal pure returns (bytes32 slot) {
        assembly {
            slot := whitelistedTargets.slot
        }
    }

    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        require(IERC20(token).transfer(owner, balance), "Transfer failed");
    }

    function updateBotAddress(address _newBot) external onlyOwner {
        botAddress = _newBot;
    }
}
