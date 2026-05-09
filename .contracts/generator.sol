// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";



contract VRFGenerator_10V is IERC777Recipient, VRFV2PlusWrapperConsumerBase {
    address public owner;
    address public treasury;
    ERC777 public immutable token;
    uint32 public callbackGasLimit = 500000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 9;

    uint256 public constant MAX_QUEUE = 300;
    uint256 public constant MIN_QUEUE = 30;
    uint256 public constant MIN_NATIVE_RESERVE = 0.01 ether;
    uint256[] public randomQueue;

    mapping(uint256 => bool) public validRequest;
    mapping(address => bool) public authorizedConsumers;

    bool private requestInFlight;

    event Received(address indexed from, uint256 amount);
    event RequestTriggered(uint256 queueSize);
    event QueueRefilled(uint256 newSize);
    event Normalized(uint256 sentToTreasury);
    event Swapped(uint256 tokenAmount);

     constructor(
        ERC777 _token,
        address wrapper
  
    )
        VRFV2PlusWrapperConsumerBase(wrapper)
    {
        owner = msg.sender;
        treasury = msg.sender;

        token = _token;
     

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

   receive() external payable {}


      modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }
    // =========================================================
    // AUTO TRIGGER VIA TOKEN RECEIVED
    // =========================================================
    function tokensReceived(
        address,
        address from,
        address,
        uint256 amount,
        bytes calldata,
        bytes calldata
    )external override onlyValidToken {
        require(from != address(0), "Invalid sender");

        emit Received(from, amount);

        _ensureBuffer();
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
        require(randomQueue.length > 0, "empty");

        uint256 value = randomQueue[randomQueue.length - 1];
        randomQueue.pop();

        _ensureBuffer();

        return value;
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
    function setAuthorized(address consumer, bool allowed) external onlyOwner {
        authorizedConsumers[consumer] = allowed;
    }

    function withdrawToken(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "invalid recipient");
        token.send(to, amount, "");
    }

}