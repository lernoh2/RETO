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

    // ================= BET CONFIG =================
    // Only BET needs to change at deploy time. Every other tier and every
    // fee / contribution / reserve amount is derived from it as a percentage,
    // the same way the 3-step contract derives fee/contribution from `amount`.

    uint256 public constant BET = 299.7 ether;

    // Basis points (10000 = 100%). These ratios are fixed regardless of BET.
    uint256 public constant FEE_BP             = 690;  // 6.9%   generator fee
    uint256 public constant CONTRIBUTION_BP    = 9000;  // 90%   goes to pool
    uint256 public constant SELLER_RESERVE_BP  = 1000;  // 10%   extra reserve for sellers
    uint256 public constant BUYER_RESERVE_BP   = 46000; // 460%  extra reserve for buyers

    uint256 public constant GENERATOR_FEE = (BET * FEE_BP) / 10000;
    uint256 public constant CONTRIBUTION  = (BET * CONTRIBUTION_BP) / 10000;
    uint256 public constant SELLER_RESERVE = (BET * SELLER_RESERVE_BP) / 10000;
    uint256 public constant BUYER_RESERVE  = (BET * BUYER_RESERVE_BP) / 10000;

    uint256 public constant SellBET       = BET + SELLER_RESERVE;
    uint256 public constant BuyBET        = BET + BUYER_RESERVE;
    uint256 public constant BuyOrSellBET  = BET + SELLER_RESERVE + BUYER_RESERVE;

    uint256 public constant MAX_PLAYERS = 128;
    uint8 public constant MARKET_STEP = 4;

    enum State {
        OPEN,
        LOCKED
    }

    // Roles used for claim bookkeeping / event labeling.
    enum ClaimRole {
        FAILED_BUYER_REFUND,
        SELLER_PAYOUT,      
        CHAMPION,
        RUNNER_UP,
        THIRD,
        FOURTH
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
    // Reverse lookup: buyer => seller they were matched with in the market phase.
    mapping(address => address) public buyerToSeller;
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

    // Claimable balance per address, persists across cycles indefinitely.
    mapping(address => uint256) public claimableBalance;

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

    // Fired when a payout is credited, before the recipient withdraws.
    event ClaimableCredited(
        address indexed account,
        uint256 indexed cycleId,
        ClaimRole role,
        uint256 amount
    );

    // Fired when the recipient withdraws via claim().
    event Claimed(
        address indexed account,
        uint256 totalAmount
    );

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
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
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
        require(!_isContract(from), "EOA only");
        require(state == State.OPEN, "not open");
        require(playersCount < MAX_PLAYERS, "full");
        require(!joined[from], "already joined");
        require(
            amount == BET ||
            amount == SellBET ||
            amount == BuyBET ||
            amount == BuyOrSellBET,
            "must send exact bet"
        );

        emit Received(from, amount);

        // ================= NORMAL JOIN =================
        if (amount == BET) {
            token.send(address(generator), GENERATOR_FEE, "");
            pool += CONTRIBUTION;

            _join(from);
        }

        // ================= POTENTIAL SELLER =================
        else if (amount == SellBET) {
            token.send(address(generator), GENERATOR_FEE, "");
            pool += CONTRIBUTION;
            tradersReserve += SELLER_RESERVE;

            isSeller[from] = true;
            sellers.push(from);

            emit SellerRegistered(cycleId, from, sellers.length);

            _join(from);
        }

        // ================= POTENTIAL BUYER =================
        else if (amount == BuyBET) {
            token.send(address(generator), GENERATOR_FEE, "");
            pool += CONTRIBUTION;
            tradersReserve += BUYER_RESERVE;

            isBuyer[from] = true;
            buyers.push(from);

            emit BuyerRegistered(cycleId, from, buyers.length);

            _join(from);
        }

        // ================= POTENTIAL BUYER OR SELLER =================
        else if (amount == BuyOrSellBET) {
            token.send(address(generator), GENERATOR_FEE, "");
            pool += CONTRIBUTION;
            tradersReserve += (SELLER_RESERVE + BUYER_RESERVE);

            isBuyer[from] = true;
            buyers.push(from);

            isSeller[from] = true;
            sellers.push(from);

            emit BuyerRegistered(cycleId, from, buyers.length);
            emit SellerRegistered(cycleId, from, sellers.length);

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

    function _shufflePlayers(
        address[] memory input,
        uint256 randomSeed
    ) internal pure returns (address[] memory) {
        uint256 n = input.length;
        address[] memory shuffled = new address[](n);

        for (uint256 i = 0; i < n; i++) {
            shuffled[i] = input[i];
        }

        for (uint256 i = n; i > 1; i--) {
            uint256 j = uint256(keccak256(abi.encode(randomSeed, i))) % i;
            address tmp = shuffled[i - 1];
            shuffled[i - 1] = shuffled[j];
            shuffled[j] = tmp;
        }

        return shuffled;
    }

    // ================= RESOLUTION =================

    function _resolve() internal {
        require(state == State.LOCKED, "not locked");

        if (generator.queueSize() < 3) {
            generator.requestBatch();
            revert("VRF not ready");
        }

        uint256 randPlayers = generator.consumeRandom();
        uint256 randStages  = generator.consumeRandom();
        uint256 randPairs   = generator.consumeRandom();

        address[] memory round = _shufflePlayers(players, randPlayers);

        for (uint8 step = 1; step <= 8; step++) {

            if (step == MARKET_STEP) {
                _marketPhase(round);

                round = _shufflePlayers(
                    postMarketFinalists,
                    uint256(keccak256(abi.encode(randStages, step)))
                );

                continue;
            }

            uint256 stepShuffle = uint256(
                keccak256(abi.encode(randStages, step, round.length))
            );

            uint256 stepPairs = uint256(
                keccak256(abi.encode(randPairs, step, round.length))
            );

            round = _shufflePlayers(round, stepShuffle);

            address[] memory next = _nextRound(round, step, stepShuffle, stepPairs);

            if (step == 7) {
                semiFinalLosers = lastRoundLosers;
            }

            if (step == 8) {
                finalLosers = lastRoundLosers;
            }

            round = next;
        }

        _settleTrades();

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

        address[] memory shuffled = _shufflePlayers(playersInput, randShuffle);

        address[] memory winners = new address[](n / 2);
        address[] memory losers  = new address[](n / 2);

        for (uint256 i = 0; i < n / 2; i++) {
            address p1 = shuffled[2 * i];
            address p2 = shuffled[2 * i + 1];

            uint256 entropy = uint256(
                keccak256(abi.encode(randOutcome, step, i, p1, p2))
            );

            if (entropy & 1 == 0) {
                winners[i] = p1;
                losers[i]  = p2;
            } else {
                winners[i] = p2;
                losers[i]  = p1;
            }
        }

        delete lastRoundWinners;
        delete lastRoundLosers;

        for (uint256 i = 0; i < winners.length; i++) {
            lastRoundWinners.push(winners[i]);
            lastRoundLosers.push(losers[i]);
        }

        for (uint256 i = 0; i < losers.length; i++) {
            allLosers.push(losers[i]);
            wasEliminated[losers[i]] = true;
        }

        return winners;
    }

    function _marketPhase(address[] memory round) internal {
        emit TradingPhaseStarted(cycleId);

        delete postMarketFinalists;
        delete matchedBuyers;
        delete matchedSellers;
        delete failedBuyers;
        delete failedSellers;

        uint256 matches;

        for (uint256 i = 0; i < round.length; i++) {
            postMarketFinalists.push(round[i]);
        }

        for (uint256 i = 0; i < buyers.length; i++) {
            address b = buyers[i];
            if (wasEliminated[b] && !buyerMatched[b]) {
                failedBuyers.push(b);
            }
        }

        for (uint256 i = 0; i < sellers.length; i++) {
            address s = sellers[i];
            if (wasEliminated[s]) {
                failedSellers.push(s);
            }
        }

        uint256 pairCount = failedBuyers.length < round.length
            ? failedBuyers.length
            : round.length;

        uint256 sellerIndex;

        for (uint256 i = 0; i < pairCount; i++) {
            address seller;

            while (sellerIndex < round.length) {
                address candidate = round[sellerIndex++];
                if (isSeller[candidate]) {
                    seller = candidate;
                    break;
                }
            }

            if (seller == address(0)) break;

            address buyer = failedBuyers[i];

            seatSwap[seller]     = buyer;
            buyerToSeller[buyer] = seller;   // reverse mapping
            buyerMatched[buyer]  = true;

            matchedBuyers.push(buyer);
            matchedSellers.push(seller);

            emit TradingPairFormed(cycleId, i, seller, buyer);

            for (uint256 j = 0; j < postMarketFinalists.length; j++) {
                if (postMarketFinalists[j] == seller) {
                    postMarketFinalists[j] = buyer;
                    break;
                }
            }

            matches++;
        }

        emit TradingPhaseFinished(cycleId, matches);
    }

    function _settleTrades() internal {
        uint256 sellerPayouts;
        uint256 buyerRefunds;

        uint256 len = allLosers.length;

        // PASS 1: calculate totals
        for (uint256 i = 0; i < len; i++) {
            address buyer = allLosers[i];
            if (!isBuyer[buyer]) continue;

            if (buyerMatched[buyer]) {
                sellerPayouts += BUYER_RESERVE;
            } else {
                buyerRefunds += BUYER_RESERVE;
            }
        }

        uint256 totalNeeded = sellerPayouts + buyerRefunds;
        require(tradersReserve >= totalNeeded, "reserve insufficient");
        tradersReserve -= totalNeeded;

        // PASS 2: credit claimable balances
        for (uint256 i = 0; i < len; i++) {
            address buyer = allLosers[i];
            if (!isBuyer[buyer]) continue;

            if (buyerMatched[buyer]) {
                // Direct O(1) reverse-mapping lookup — no scan needed.
                address seller = buyerToSeller[buyer];
                require(seller != address(0), "seller missing");

                claimableBalance[seller] += BUYER_RESERVE;

                emit ClaimableCredited(
                    seller,
                    cycleId,
                    ClaimRole.SELLER_PAYOUT,   // ← corrected role
                    BUYER_RESERVE
                );
            } else {
                claimableBalance[buyer] += BUYER_RESERVE;

                emit ClaimableCredited(
                    buyer,
                    cycleId,
                    ClaimRole.FAILED_BUYER_REFUND,
                    BUYER_RESERVE
                );

                emit BuyerRefunded(cycleId, buyer, BUYER_RESERVE);
            }
        }
    }

    function _distributePrizes(
        address champion,
        address runnerUp
    ) internal {
        address third  = semiFinalLosers[0];
        address fourth = semiFinalLosers[1];

        uint256 finalPrizePool = pool + tradersReserve;
        require(finalPrizePool > 0, "empty pool");

        uint256 championShare = (finalPrizePool * 5000) / 10000;
        uint256 runnerUpShare = (finalPrizePool * 2000) / 10000;
        uint256 thirdShare    = (finalPrizePool * 1500) / 10000;
        uint256 fourthShare   = (finalPrizePool * 1500) / 10000;

        require(
            championShare + runnerUpShare + thirdShare + fourthShare <= finalPrizePool,
            "math overflow"
        );

        claimableBalance[champion] += championShare;
        emit ClaimableCredited(champion, cycleId, ClaimRole.CHAMPION, championShare);

        claimableBalance[runnerUp] += runnerUpShare;
        emit ClaimableCredited(runnerUp, cycleId, ClaimRole.RUNNER_UP, runnerUpShare);

        claimableBalance[third] += thirdShare;
        emit ClaimableCredited(third, cycleId, ClaimRole.THIRD, thirdShare);

        claimableBalance[fourth] += fourthShare;
        emit ClaimableCredited(fourth, cycleId, ClaimRole.FOURTH, fourthShare);

        emit Finished(cycleId, champion, championShare);
    }

    function _reset() internal {
        for (uint256 i = 0; i < players.length; i++) {
            address p = players[i];

            joined[p]        = false;
            isSeller[p]      = false;
            isBuyer[p]       = false;
            wasEliminated[p] = false;
            buyerMatched[p]  = false;

            // Clear the reverse mapping before zeroing seatSwap,
            // using the seat-swap entry to find which buyer to clear.
            address buyer = seatSwap[p];
            if (buyer != address(0)) {
                buyerToSeller[buyer] = address(0);
            }

            seatSwap[p]     = address(0);
            buyerToSeller[p] = address(0); // also zero out if this address was itself a buyer
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

        playersCount  = 0;
        pool          = 0;
        tradersReserve = 0;
        tradingDone   = false;

        cycleId++;
        state = State.OPEN;

        // NOTE: claimableBalance intentionally NOT cleared here.
        // Credits from any past cycle remain withdrawable indefinitely.
    }

    // ================= CLAIM =================

    function claim() external nonReentrant {
        uint256 amount = claimableBalance[msg.sender];
        require(amount > 0, "nothing claimable");

        claimableBalance[msg.sender] = 0;
        token.send(msg.sender, amount, "");

        emit Claimed(msg.sender, amount);
    }
}
