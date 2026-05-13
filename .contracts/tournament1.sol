// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";

interface IVRFGenerator {
    function requestBatch() external;
    function consumeRandom() external returns (uint256);
    function queueSize() external view returns (uint256);
}

contract GarettoTournament_1 is IERC777Recipient, ReentrancyGuard {
    IERC1820Registry private constant _ERC1820_REGISTRY =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    address public owner;
    ERC777 public immutable token;
    IVRFGenerator public generator;

    uint256 public constant BET = 994 ether;
    uint256 public constant MAX_PLAYERS = 4;

    enum State {
        OPEN,
        LOCKED
    }
  
    State public state;

    address[] public players;
    mapping(address => bool) public joined;
     struct Rand {
    uint256 value;
    bool isVRF;
}
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

    modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }

    function tokensReceived(
        address,
        address from,
        address,
        uint256 amount,
        bytes calldata,
        bytes calldata
    ) external override onlyValidToken {
        require(from != address(0), "Invalid sender");
        require(state == State.OPEN, "not open");
        require(playersCount < MAX_PLAYERS, "full");
        require(!joined[from], "already joined");
        require(amount == BET, "must send exactly 99.4");

        emit Received(from, amount);

        uint256 fee = (amount * 10) / 100;
        uint256 contribution = amount - fee;

        token.send(address(generator), fee, "");

        pool += contribution;
        players.push(from);
        joined[from] = true;
        playersCount++;

        emit Joined(from, cycleId, playersCount);

        if (playersCount == MAX_PLAYERS) {
             state = State.LOCKED;
            _getRandom();
            _resolve();
          
        }
    }
 
    function _getRandom() internal returns (Rand memory) {
    if (generator.queueSize() > 0) {
        return Rand({
            value: generator.consumeRandom(),
            isVRF: true
        });
    } else {
        return Rand({
            value: uint256(
                keccak256(
                    abi.encode(
                        block.prevrandao,
                        msg.sender,
                        playersCount,
                        block.timestamp
                    )
                )
            ),
            isVRF: false
        });
    }
}
    // ================= RESOLUTION =================

   function _resolve() internal {
    require(state == State.LOCKED);

    uint256 base;

    if (generator.queueSize() == 0) {
        generator.requestBatch();
        base = uint256(keccak256(abi.encode(block.prevrandao)));
    } else {
        base = generator.consumeRandom();
    }

    address[] memory round = players;
    uint256 seed = base;

    // 4 -> 2 -> 1
    for (uint8 step = 1; step <= 2; step++) {
        uint256 randShuffle;
        uint256 randOutcome;

        if (generator.queueSize() >= 2) {
            randShuffle = generator.consumeRandom();
            randOutcome = generator.consumeRandom();
        } else {
            generator.requestBatch();
            randShuffle = uint256(
                keccak256(abi.encode(seed, step, "S"))
            );
            randOutcome = uint256(
                keccak256(abi.encode(seed, step, "O"))
            );
        }

        round = _nextRound(
            round,
            step,
            randShuffle,
            randOutcome
        );

        seed = uint256(
            keccak256(
                abi.encode(seed, randShuffle, randOutcome)
            )
        );
    }

    address winner = round[0];
    uint256 prize = pool;

    token.send(winner, prize, "");
    emit Finished(cycleId, winner, prize);

    _reset();
}

    // ================= ROUND =================

function _nextRound(
    address[] memory playersInput,
    uint8 step,
    uint256 randShuffle,
    uint256 randOutcome
) internal returns (address[] memory) {

    uint256 n = playersInput.length;

    // ================= INLINE SHUFFLE =================
    address[] memory shuffled = playersInput;

    for (uint256 i = n; i > 1; i--) {
        uint256 j = uint256(keccak256(abi.encode(randShuffle, i))) % i;

        address tmp = shuffled[i - 1];
        shuffled[i - 1] = shuffled[j];
        shuffled[j] = tmp;
    }

    uint256 nextSize = n / 2;
    address[] memory winners = new address[](nextSize);
    address[] memory losers = new address[](nextSize);

    // ================= INLINE COEFF =================
    uint256 coeff;
    for (uint256 i = 0; i < n; i++) {
        coeff += uint160(shuffled[i]);
    }
    coeff = coeff % 997;

    // ================= INLINE MATCH LOGIC =================
    for (uint256 i = 0; i < nextSize; i++) {
        address p1 = shuffled[2 * i];
        address p2 = shuffled[2 * i + 1];

        uint256 entropy = uint256(
            keccak256(
                abi.encode(randOutcome, coeff, step, i, p1, p2)
            )
        );

        uint256 base = entropy % 1000;

        uint256 a = uint160(p1) % 100;
        uint256 b = uint160(p2) % 100;

        int256 scoreSigned = int256(base) + int256(a) - int256(b);

        uint256 score = scoreSigned < 0
            ? uint256(-scoreSigned)
            : uint256(scoreSigned);

        uint256 threshold = coeff / 2;

        bool p1wins;

        if ((entropy & 1) == 0) {
            p1wins = score >= threshold;
        } else {
            p1wins = score <= threshold;
        }

        if (p1wins) {
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