// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";


interface IVRFGenerator {
    function requestBatch() external;
    function consumeRandom() external returns (uint256);
    function queueSize() external view returns (uint256);
}

contract Garetto_Tournament_2step_BET300 is IERC777Recipient, ReentrancyGuard {

    IERC1820Registry private constant _ERC1820_REGISTRY =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    address public owner;
    ERC777 public immutable token;
    IVRFGenerator public generator;

    uint256 public constant BET = 299.7 ether;
    uint256 public constant MAX_PLAYERS = 4;

    enum State { OPEN, LOCKED }
    State public state;

    address[] public players;
    mapping(address => bool) public joined;

    uint256 public playersCount;
    uint256 public pool;
    uint256 public cycleId;

    event Joined(address indexed player, uint256 indexed cycleId, uint256 playersCount);
    event Received(address indexed from, uint256 amount);

    event RoundResolved(
        uint256 indexed cycleId,
        uint8 indexed step,
        address[] shuffledPlayers,
        address[] winners,
        address[] losers
    );

    event Finished(uint256 indexed cycleId, address indexed winner, uint256 prize);

    constructor(ERC777 _token, address _generator) {
        _ERC1820_REGISTRY.setInterfaceImplementer(
            address(this),
            keccak256("ERC777TokensRecipient"),
            address(this)
        );

        owner = msg.sender;
        token = _token;
        generator = IVRFGenerator(_generator);
        cycleId = 1;
        state = State.OPEN;
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }

    // ================= ENTRY =================

    function tokensReceived(
        address,
        address from,
        address,
        uint256 amount,
        bytes calldata,
        bytes calldata
    )
        external
        override
        onlyValidToken
        nonReentrant
    {
        require(from != address(0) && from != owner, "Invalid sender");
        require(!_isContract(from), "EOA only");
        require(state == State.OPEN, "not open");
        require(playersCount < MAX_PLAYERS, "full");
        require(!joined[from], "already joined");
        require(amount == BET, "must send exact bet");

        emit Received(from, amount);

        uint256 fee = (amount * 69) / 1000;
        uint256 contribution = amount - fee;

        token.send(address(generator), fee, "");

        pool += contribution;

        players.push(from);
        joined[from] = true;
        playersCount++;

        emit Joined(from, cycleId, playersCount);

        if (playersCount == MAX_PLAYERS) {
            state = State.LOCKED;
            _resolve();
        }
    }

    // ================= RESOLUTION =================

    function _resolve() internal {
        require(state == State.LOCKED, "not locked");

        require(generator.queueSize() >= 3, "VRF not ready");

        address[] memory round = players;

        for (uint8 step = 1; step <= 2; step++) {

            require(generator.queueSize() >= 3, "VRF not ready");

            uint256 seedPlayers = generator.consumeRandom();
            uint256 seedRound   = generator.consumeRandom();
            uint256 seedPairs   = generator.consumeRandom();

            // ONLY shuffle ONCE per step (correct fix)
            round = _shuffle(round, seedPlayers);

            round = _nextRound(
                round,
                step,
                seedRound,
                seedPairs
            );
        }

        uint256 prize = pool;
        token.send(round[0], prize, "");

        emit Finished(cycleId, round[0], prize);

        _reset();
    }

    // ================= ROUND =================

    function _nextRound(
        address[] memory playersInput,
        uint8 step,
        uint256 seedRound,
        uint256 seedPairs
    ) internal returns (address[] memory) {

        uint256 n = playersInput.length;

        address[] memory shuffled = _shuffle(playersInput, seedRound);

        uint256 nextSize = n / 2;
        address[] memory winners = new address[](nextSize);
        address[] memory losers = new address[](nextSize);

        for (uint256 i = 0; i < nextSize; i++) {

            address p1 = shuffled[2 * i];
            address p2 = shuffled[2 * i + 1];

            uint256 bit = uint256(
                keccak256(abi.encode(seedPairs, step, i, p1, p2))
            ) & 1;

            if (bit == 0) {
                winners[i] = p1;
                losers[i] = p2;
            } else {
                winners[i] = p2;
                losers[i] = p1;
            }
        }

        emit RoundResolved(cycleId, step, shuffled, winners, losers);

        return winners;
    }

    // ================= SHUFFLE =================

    function _shuffle(
        address[] memory input,
        uint256 seed
    ) internal pure returns (address[] memory) {

        uint256 n = input.length;
        address[] memory arr = new address[](n);

        for (uint256 i = 0; i < n; i++) {
            arr[i] = input[i];
        }

        for (uint256 i = n; i > 1; i--) {

            uint256 j = uint256(
                keccak256(abi.encode(seed, i))
            ) % i;

            (arr[i - 1], arr[j]) = (arr[j], arr[i - 1]);
        }

        return arr;
    }

    // ================= RESET =================

    function _reset() internal {
        for (uint256 i = 0; i < players.length; i++) {
            joined[players[i]] = false;
        }

        delete players;
        playersCount = 0;
        pool = 0;
        cycleId++;
        state = State.OPEN;
    }
}