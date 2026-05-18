// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";

interface IVRFGenerator {
    function requestBatch() external;
    function consumeRandom() external returns (uint256);
    function queueSize() external view returns (uint256);
}

contract GarettoTournament_7Step128 is IERC777Recipient, ReentrancyGuard {
    IERC1820Registry private constant _ERC1820_REGISTRY =
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    address public owner;
    ERC777 public immutable token;
    IVRFGenerator public generator;

    uint256 public constant BET = 994 ether;
    uint256 public constant SellBET = 1093.4 ether;
    uint256 public constant BuyBET = 8449 ether;
    uint256 public constant MAX_PLAYERS = 128;
    uint8 public constant MARKET_STEP = 4;

    enum State {
        OPEN,
        LOCKED
    }
  
    State public state;
    address[] public sellers;
    address[] public buyers;
    address[] public players;
    address[] public postMarketFinalists;
    address[] public failedBuyers;
    address[] public failedSellers;
    address[] public matchedBuyers;
    address[] public matchedSellers;
    address[] public lastRoundLosers;
    address[] public lastRoundWinners;
    address[] public semiFinalLosers;
    address[] public finalLosers;
    mapping(address => address) public seatSwap;
    mapping(address => bool) public isSeller;
    mapping(address => bool) public isBuyer;
    mapping(address => bool) public buyerMatched;
    mapping(address => bool) public joined;
    mapping(address => bool) public wasEliminated;
    address[] public allLosers;
    uint256 public tradersReserve;
    

    uint256 public playersCount;
    uint256 public pool;
    uint256 public cycleId;

    bool public tradingDone;

    event Joined(address indexed player, uint256 indexed cycleId, uint256 playersCount);
    event Received(address indexed from, uint256 amount);
    event RoundResolved(
        uint256 indexed cycleId,
        uint8 indexed step,
        address[] shuffledPlayers,
        address[] winners,
        address[] losers
    );
   event SellerRegistered(
    uint256 indexed cycleId,
    address indexed seller,
    uint256 totalSellers
);

event BuyerRegistered(
    uint256 indexed cycleId,
    address indexed buyer,
    uint256 totalBuyers
);

event TradeMatched(
    uint256 indexed cycleId,
    address indexed seller,
    address indexed buyer
);

event BuyerRefunded(
    uint256 indexed cycleId,
    address indexed buyer,
    uint256 amount
);

event SellerUnmatched(
    uint256 indexed cycleId,
    address indexed seller
);

event TradingPhaseStarted(
    uint256 indexed cycleId
);

event TradingPairFormed(
    uint256 indexed cycleId,
    uint256 indexed pairId,
    address indexed seller,
    address buyer
);

event TradingPhaseFinished(
    uint256 indexed cycleId,
    uint256 matchedTrades
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
) external override onlyValidToken nonReentrant {

    require(from != address(0), "Invalid sender");
    require(state == State.OPEN, "not open");

    emit Received(from, amount);

    // ================= NORMAL JOIN =================
    if (amount == BET) {

        uint256 generatorFee = 99.4 ether;
        uint256 contribution = 894.6 ether;

        token.send(address(generator), generatorFee, "");

        pool += contribution;

        _join(from);
    }

    // ================= POTENTIAL SELLER =================
    else if (amount == SellBET) {

        uint256 generatorFee = 99.4 ether;
        uint256 contribution = 894.6 ether;

        // 1093.4 - 894.6 - 99.4 = 99.4
        uint256 reserveAmount = 99.4 ether;

        token.send(address(generator), generatorFee, "");

        pool += contribution;

        tradersReserve += reserveAmount;

       isSeller[from] = true;

        sellers.push(from);

        emit SellerRegistered(
            cycleId,
            from,
            sellers.length
        );

        _join(from);
    }

    // ================= POTENTIAL BUYER =================
    else if (amount == BuyBET) {

        uint256 generatorFee = 99.4 ether;
        uint256 contribution = 894.6 ether;

        // 8449 - 894.6 - 99.4 = 7455
        uint256 reserveAmount = 7455 ether;

        token.send(address(generator), generatorFee, "");

        pool += contribution;

        tradersReserve += reserveAmount;

       isBuyer[from] = true;

        buyers.push(from);

        emit BuyerRegistered(
            cycleId,
            from,
            buyers.length
        );

        _join(from);
    }

    else {
        revert("invalid amount");
    }
}
 
 function _join(address from) internal {

    require(playersCount < MAX_PLAYERS, "full");
    require(!joined[from], "already joined");
    
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

    address[] memory round = players;

      uint256 base;

            if (generator.queueSize() == 0) {
                generator.requestBatch();
                base = uint256(keccak256(abi.encode(block.prevrandao)));
            } else {
                base = generator.consumeRandom();
            }
      
        uint256 seed = base;

    for (uint8 step = 1; step <= 8; step++) {

        if (step == MARKET_STEP) {
            _marketPhase();
            round = postMarketFinalists;
            continue;
        }
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

        address[] memory next = _nextRound(
            round,
            step,
            randShuffle,
            randOutcome
        );

        // capture semifinal + final losers correctly
        if (step == 7) {
           semiFinalLosers = lastRoundLosers;
        }

        if (step == 8) {
            finalLosers = lastRoundLosers;
        }

        round = next;

        seed = uint256(keccak256(abi.encode(seed, randShuffle, randOutcome)));
    }
    _settleTrades();
    // round[0] = champion
    // round[1] = runner up
    _distributePrizes(round[0], round[1]);

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

    uint256 coeff;
    for (uint256 i = 0; i < n; i++) {
        coeff += uint160(shuffled[i]);
    }
    coeff = coeff % 997;

    for (uint256 i = 0; i < nextSize; i++) {

        address p1 = shuffled[2 * i];
        address p2 = shuffled[2 * i + 1];

        uint256 entropy = uint256(
            keccak256(abi.encode(randOutcome, coeff, step, i, p1, p2))
        );

        uint256 base = entropy % 1000;

        uint256 a = uint160(p1) % 100;
        uint256 b = uint160(p2) % 100;

        int256 scoreSigned = int256(base) + int256(a) - int256(b);

        uint256 score = scoreSigned < 0
            ? uint256(-scoreSigned)
            : uint256(scoreSigned);

        uint256 threshold = coeff / 2;

        bool p1wins = ((entropy & 1) == 0)
            ? (score >= threshold)
            : (score <= threshold);

        if (p1wins) {
            winners[i] = p1;
            losers[i] = p2;
        } else {
            winners[i] = p2;
            losers[i] = p1;
        }
    }

    // ✅ IMPORTANT FIX: mark elimination ONCE, no scanning later
    for (uint256 i = 0; i < losers.length; i++) {
        address l = losers[i];

        allLosers.push(l);
        wasEliminated[l] = true;
    }

    delete lastRoundWinners;
    delete lastRoundLosers;

    for (uint256 i = 0; i < winners.length; i++) {
        lastRoundWinners.push(winners[i]);
    }

    for (uint256 i = 0; i < losers.length; i++) {
        lastRoundLosers.push(losers[i]);
    }

    emit RoundResolved(cycleId, step, shuffled, winners, losers);

    return winners;
}

function _marketPhase() internal {

    emit TradingPhaseStarted(cycleId);

    delete postMarketFinalists;
    delete matchedBuyers;
    delete matchedSellers;
    delete failedBuyers;
    delete failedSellers;

    uint256 matches;

    for (uint256 i = 0; i < lastRoundWinners.length; i++) {
        postMarketFinalists.push(lastRoundWinners[i]);
    }

    // =============================
    // FIXED ELIMINATION LOGIC (O(n))
    // =============================
    for (uint256 i = 0; i < buyers.length; i++) {

        address b = buyers[i];

        if (wasEliminated[b] && !buyerMatched[b]) {
            failedBuyers.push(b);
        }
    }

    // sellers filter (still O(n), OK)
    for (uint256 i = 0; i < sellers.length; i++) {

        address s = sellers[i];

        bool finalist = false;

        for (uint256 j = 0; j < lastRoundWinners.length; j++) {
            if (lastRoundWinners[j] == s) {
                finalist = true;
                break;
            }
        }

        if (!finalist) {
            failedSellers.push(s);

            emit SellerUnmatched(cycleId, s);
        }
    }

    uint256 pairCount =
        failedBuyers.length < lastRoundWinners.length
            ? failedBuyers.length
            : lastRoundWinners.length;

    uint256 sellerIndex;

    for (uint256 i = 0; i < pairCount; i++) {

        address seller;

        while (sellerIndex < lastRoundWinners.length) {

            address candidate = lastRoundWinners[sellerIndex];
            sellerIndex++;

            if (isSeller[candidate]) {
                seller = candidate;
                break;
            }
        }

        if (seller == address(0)) break;

        address buyer = failedBuyers[i];

        seatSwap[seller] = buyer;
        buyerMatched[buyer] = true;

        matchedBuyers.push(buyer);
        matchedSellers.push(seller);

        emit TradeMatched(cycleId, seller, buyer);

        for (uint256 j = 0; j < postMarketFinalists.length; j++) {
            if (postMarketFinalists[j] == seller) {
                postMarketFinalists[j] = buyer;
                break;
            }
        }

        matches++;

        emit TradingPairFormed(cycleId, matches, seller, buyer);
    }

    emit TradingPhaseFinished(cycleId, matches);
}

function _settleTrades() internal {

    uint256 sellerPayouts;
    uint256 buyerRefunds;

    uint256 len = allLosers.length;

    // ==============================
    // PASS 1: CALCULATE TOTALS
    // ==============================
    for (uint256 i = 0; i < len; i++) {

        address buyer = allLosers[i];

        if (!isBuyer[buyer]) {
            continue;
        }

        if (buyerMatched[buyer]) {

            sellerPayouts += 7455 ether;

        } else {

            buyerRefunds += 7455 ether;
        }
    }

    uint256 totalNeeded =
        sellerPayouts +
        buyerRefunds;

    require(
        tradersReserve >= totalNeeded,
        "reserve insufficient"
    );

    // ======================================
    // RESERVE CONSUMED DETERMINISTICALLY
    // ======================================
    tradersReserve -= totalNeeded;

   // ==============================
// PASS 2: EXECUTE TRANSFERS
// ==============================
for (uint256 i = 0; i < len; i++) {

    address buyer = allLosers[i];

    if (!isBuyer[buyer]) {
        continue;
    }

    // ==========================
    // SUCCESSFUL BUY
    // ==========================
    if (buyerMatched[buyer]) {

        address seller;

        for (uint256 j = 0; j < players.length; j++) {

            address possibleSeller = players[j];

            if (
                seatSwap[possibleSeller] == buyer
            ) {
                seller = possibleSeller;
                break;
            }
        }

        require(
            seller != address(0),
            "seller missing"
        );

        token.send(
            seller,
            7455 ether,
            ""
        );
    }

    // ==========================
    // FAILED BUY -> REFUND
    // ==========================
    else {

        token.send(
            buyer,
            7455 ether,
            ""
        );

        emit BuyerRefunded(
            cycleId,
            buyer,
            7455 ether
        );
    }
}
    
}

function _distributePrizes(
    address champion,
    address runnerUp
) internal {

    address third = semiFinalLosers[0];
    address fourth = semiFinalLosers[1];

    uint256 finalPrizePool = pool + tradersReserve;

    require(finalPrizePool > 0, "empty pool");

    // basis points
    uint256 championShare = (finalPrizePool * 5000) / 10000;
    uint256 runnerUpShare = (finalPrizePool * 2000) / 10000;
    uint256 thirdShare = (finalPrizePool * 1500) / 10000;
    uint256 fourthShare = (finalPrizePool * 1500) / 10000;

    // optional sanity check (should always hold unless rounding edge)
    require(
        championShare + runnerUpShare + thirdShare + fourthShare <= finalPrizePool,
        "math overflow"
    );

    token.send(champion, championShare, "");
    token.send(runnerUp, runnerUpShare, "");
    token.send(third, thirdShare, "");
    token.send(fourth, fourthShare, "");
}

 function _reset() internal {

    for (uint256 i = 0; i < players.length; i++) {

        joined[players[i]] = false;

        isSeller[players[i]] = false;

        isBuyer[players[i]] = false;

        seatSwap[players[i]] = address(0);
        buyerMatched[players[i]] = false;
    }

    delete players;
    delete sellers;
    delete buyers;
    delete postMarketFinalists;
    delete allLosers;
    delete failedBuyers;
    delete failedSellers;
    delete matchedBuyers;
    delete matchedSellers;
    delete lastRoundLosers;
    delete lastRoundWinners;
    delete semiFinalLosers;
    delete finalLosers;
    playersCount = 0;

    pool = 0;

    tradersReserve = 0;

    tradingDone = false;

    cycleId++;

    state = State.OPEN;
}
}