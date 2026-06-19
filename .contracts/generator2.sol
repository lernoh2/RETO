// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


import "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

interface IUniswapV2Router02 {
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

contract Garetto_VRFGenerator is IERC777Recipient, VRFV2PlusWrapperConsumerBase {
    
    address public owner;
    address public treasury;
    ERC777 public immutable token;

    // ================= VRF =================
    uint32 public callbackGasLimit = 700000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 9;

    uint256 public constant MAX_QUEUE = 300;
    uint256 public constant MIN_QUEUE = 30;

    uint256[] public randomQueue;

    mapping(uint256 => bool) public validRequest;
    mapping(address => bool) public authorizedConsumers;

    bool private requestInFlight;

    // ================= UNISWAP =================
    IUniswapV2Router02 public router;
    address[] public swapPath;

    // ================= CONFIG =================
    uint256 public minNativeBalance = 0.001 ether;
    uint256 public targetNativeBalance = 0.003 ether;
    uint256 public minTokenBalance = 1000 ether;

    uint256 public maxSlippageBps = 300;
    uint256 public lastSellTime;
    uint256 public lastSellBlock;
    uint256 public maxSellPerTx = 200 ether;

 

    // ================= EVENTS =================
    event Received(address indexed from, uint256 amount);
    event RequestTriggered(uint256 queueSize);
    event QueueRefilled(uint256 newSize);
    event Swapped(uint256 tokenAmount, uint256 ethReceived);
    event MaxSellPerTxUpdated(uint256 newMax);
    event TreasuryUpdated(
    address indexed oldTreasury,
    address indexed newTreasury
);

    constructor(
        ERC777 _token,
        address wrapper,
        address _router,
        address _weth
    ) VRFV2PlusWrapperConsumerBase(wrapper) {

        owner = msg.sender;
        treasury = msg.sender;
        token = _token;

        router = IUniswapV2Router02(_router);

        swapPath.push(address(_token));
        swapPath.push(_weth);

        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(
                address(this),
                keccak256("ERC777TokensRecipient"),
                address(this)
            );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedConsumers[msg.sender], "not authorized");
        _;
    }

    modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }

    receive() external payable {}

    // =========================================================
    // ENTRY
    // =========================================================
    function tokensReceived(
    address,
    address from,
    address,
    uint256 amount,
    bytes calldata,
    bytes calldata
) external override onlyValidToken {

    require(from != address(0), "Invalid sender");
    require(authorizedConsumers[from], "not authorized"); // check `from`, not msg.sender

    emit Received(from, amount);
    _ensureBuffer();
    _autoRebalance();
}

function setMaxSellPerTx(uint256 newMax) external onlyOwner {
    require(newMax > 0, "invalid");
    require(newMax <= 10_000 ether, "too large"); // safety cap
    maxSellPerTx = newMax;
    emit MaxSellPerTxUpdated(newMax);
}

 function _autoRebalance() internal {
    uint256 nativeBal = address(this).balance;

    // enough native balance already
    if (nativeBal >= minNativeBalance) {
        return;
    }

    // anti-spam / anti-MEV
    if (
        block.timestamp < lastSellTime + 60 ||
        block.number <= lastSellBlock
    ) {
        return;
    }

    uint256 tokenBal = token.balanceOf(address(this));

    if (tokenBal < minTokenBalance) {
        return;
    }

    uint256 deficit = targetNativeBalance - nativeBal;

    if (deficit == 0) {
        return;
    }

    uint256 tokensNeeded;

    // =====================================================
    // CHECK LIQUIDITY
    // =====================================================

    try router.getAmountsIn(deficit, swapPath)
    returns (uint256[] memory amounts) {

        tokensNeeded = amounts[0];

    } catch {

        // no route / no liquidity
        return;
    }

    if (tokensNeeded == 0) {
        return;
    }

    // =====================================================
    // LIMIT SELL SIZE
    // =====================================================

    uint256 chunk = tokensNeeded;

    if (chunk > maxSellPerTx) {
        chunk = maxSellPerTx;
    }

    if (chunk > tokenBal) {
        chunk = tokenBal;
    }

    if (chunk == 0) {
        return;
    }

    // =====================================================
    // CHECK EXPECTED OUTPUT
    // =====================================================

    uint256[] memory expected;

    try router.getAmountsOut(chunk, swapPath)
    returns (uint256[] memory amounts) {

        expected = amounts;

    } catch {

        return;
    }

    if (expected.length < 2 || expected[1] == 0) {
        return;
    }

    uint256 minOut =
        (expected[1] * (10000 - maxSlippageBps))
        / 10000;

    // =====================================================
    // APPROVE
    // =====================================================

    IERC20(address(token)).approve(
        address(router),
        0
    );

    IERC20(address(token)).approve(
        address(router),
        chunk
    );

    // =====================================================
    // SWAP
    // =====================================================

    try router.swapExactTokensForETH(
        chunk,
        minOut,
        swapPath,
        address(this),
        block.timestamp
    ) returns (uint[] memory result) {

        lastSellTime = block.timestamp;
        lastSellBlock = block.number;

        emit Swapped(
            chunk,
            result[result.length - 1]
        );

    } catch {

        // swap failed
        return;
    }
}


    // =========================================================
    // PUBLIC REQUEST ENTRY
    // =========================================================
    function requestBatch() external onlyAuthorized {
        _ensureBuffer();
    }

    // =========================================================
    // CORE LOGIC (THE IMPORTANT PART)
    // =========================================================
    function _ensureBuffer() internal {
        if (randomQueue.length >= MIN_QUEUE) {
            return;
        }

        if (requestInFlight) {
            return;
        }

        requestInFlight = true;

        bytes memory extraArgs =
            VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
            );

        (uint256 requestId, ) = requestRandomnessPayInNative(
            callbackGasLimit,
            requestConfirmations,
            numWords,
            extraArgs
        );

        validRequest[requestId] = true;

        emit RequestTriggered(randomQueue.length);
    }

    // =========================================================
    // VRF CALLBACK
    // =========================================================
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        require(validRequest[requestId], "invalid");

        for (uint256 i = 0; i < randomWords.length; i++) {
            if (randomQueue.length < MAX_QUEUE) {
                randomQueue.push(randomWords[i]);
            }
        }

        requestInFlight = false;

        emit QueueRefilled(randomQueue.length);
    }

    // =========================================================
    // CONSUME RANDOM
    // =========================================================
function consumeRandom() external onlyAuthorized returns (uint256) {

    if (randomQueue.length == 0) {
        _ensureBuffer();
        return 0;
    }

    if (randomQueue.length == 1) {
        uint256 singleValue = randomQueue[0];
        randomQueue.pop();
        _ensureBuffer();
        return singleValue;
    }

    uint256 seed = randomQueue[0];

    randomQueue[0] = randomQueue[randomQueue.length - 1];
    randomQueue.pop();

    uint256 index = seed % randomQueue.length;

    uint256 selectedValue = randomQueue[index];

    randomQueue[index] = randomQueue[randomQueue.length - 1];
    randomQueue.pop();

    _ensureBuffer();

    return selectedValue;
}

    // =========================================================
    // VIEW
    // =========================================================
    function queueSize() external view returns (uint256) {
        return randomQueue.length;
    }

    // =========================================================
    // ADMIN
    // =========================================================
 function setAuthorized(address consumer, bool allowed)
    external
    onlyOwner
{
    require(consumer != address(0), "zero address");

    // owner is always allowed to be set
    if (consumer != owner) {
        require(consumer.code.length > 0, "consumer must be contract");
    }

    authorizedConsumers[consumer] = allowed;
}

function setTreasury(address newTreasury)
    external
    onlyOwner
{
    require(
        newTreasury != address(0),
        "zero address"
    );

    address oldTreasury = treasury;

    treasury = newTreasury;

    emit TreasuryUpdated(
        oldTreasury,
        newTreasury
    );
}

    function setThresholds(
        uint256 _minNative,
        uint256 _targetNative,
        uint256 _minToken
    ) external onlyOwner {
        minNativeBalance = _minNative;
        targetNativeBalance = _targetNative;
        minTokenBalance = _minToken;
    }

        function withdrawNative(
            uint256 amount
        )
            external
            onlyOwner
        {
            (bool success, ) = payable(treasury).call{
            value: amount
        }("");

        require(success, "native transfer failed");
        }

    function withdrawToken(address to, uint256 amount)
        external
        onlyOwner
    {
        token.send(to, amount, "");
    }
}