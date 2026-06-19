// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";

interface IVRFGenerator {
    function requestBatch() external;
    function consumeRandom() external returns (uint256);
    function queueSize() external view returns (uint256);
}

contract Garetto_Redistributor is IERC777Recipient, ReentrancyGuard {

    address public owner;
    ERC777 public immutable token;
    IVRFGenerator public generator;

    // ===== RESERVE =====
    uint256 public reserve;

    // ===== STATE =====
    uint256 public transfersCount;
    uint256 public cycleId;

    struct RandomTriple {
    uint256 r1;
    uint256 r2;
    uint256 r3;
}

    // ===== EVENTS =====

    event Received(address indexed from, uint256 amount);

    event Redistributed(
        address indexed to,
        uint256 amount
    );

    event ReserveProcessed(
        address indexed sender,

        uint256 r1,
        uint256 r2,
        uint256 r3,
        uint256 cycleId,
        uint256 transfers,

        bool triggered,

        uint256 profit,

        uint8 conditionId
 );

    constructor(
        ERC777 _token,
        address _generator
    ) {

        IERC1820Registry(
            0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24
        ).setInterfaceImplementer(
            address(this),
            keccak256("ERC777TokensRecipient"),
            address(this)
        );

        owner = msg.sender;
        token = _token;
        generator = IVRFGenerator(_generator);

        cycleId = 1;
    }

    modifier onlyValidToken() {
        require(
            msg.sender == address(token),
            "Invalid token"
        );
        _;
    }

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
    )
        external
        override
        onlyValidToken
        nonReentrant
    {

        require(from != address(0) && from != owner, "Invalid sender");

        emit Received(from, amount);

        // ADD TO RESERVE
        reserve += amount;

        // CONTRACT FILTER
        if (!_isContract(from)) {

            // NEED 3 RANDOMS
         if (generator.queueSize() < 1) {
            generator.requestBatch();
            return;
        }

        uint256 vrf = generator.consumeRandom();

            RandomTriple memory rnd =
                _deriveRandoms(vrf);

            _processReserve(
                from,
                rnd.r1,
                rnd.r2,
                rnd.r3
            );
        }
    }

    // =========================================================
    // CONTRACT CHECK
    // =========================================================

    function _isContract(address account)
        internal
        view
        returns (bool)
    {
        uint256 size;

        assembly {
            size := extcodesize(account)
        }

        return size > 0;
    }


    function _deriveRandoms(
        uint256 vrf
    ) internal view returns (RandomTriple memory rnd) {

    uint256 selector =
        (vrf + transfersCount + reserve + cycleId) % 2;

    if (selector == 0) {

        rnd.r1 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    transfersCount,
                    reserve
                )
            )
        );

        rnd.r2 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    cycleId,
                    address(this)
                )
            )
        );

        rnd.r3 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    reserve,
                    transfersCount,
                    cycleId
                )
            )
        );

    } else {

        rnd.r1 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    reserve,
                    cycleId
                )
            )
        );

        rnd.r2 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    transfersCount,
                    address(this)
                )
            )
        );

        rnd.r3 = uint256(
            keccak256(
                abi.encode(
                    vrf,
                    reserve,
                    transfersCount
                )
            )
        );
    }
}

    // =========================================================
    // MAIN LOGIC
    // =========================================================

function _processReserve(
    address from,
    uint256 rand1,
    uint256 rand2,
    uint256 rand3
) internal {

    uint256 eventCycleId = cycleId;

    transfersCount++;

    uint256 minRange = 2;
    uint256 maxRange;

    uint256 payoutPercent;

    uint8 conditionId;

    // =====================================================
    // CONDITION 1
    // transfers: 0 - 60
    // randoms: 2 - 90
    // payout: 10%
    // =====================================================

    if (transfersCount <= 60) {

        maxRange = 90;
        payoutPercent = 10;

        conditionId = 1;

    // =====================================================
    // CONDITION 2
    // transfers: 61 - 600
    // randoms: 2 - 900
    // payout: 30%
    // =====================================================

    } else if (
        transfersCount >= 61 &&
        transfersCount <= 600
    ) {

        maxRange = 900;
        payoutPercent = 30;

        conditionId = 2;

    // =====================================================
    // CONDITION 3
    // transfers: 601 - 6000
    // randoms: 2 - 9000
    // payout: 60%
    // =====================================================

    } else if (
        transfersCount >= 601 &&
        transfersCount <= 6000
    ) {

        maxRange = 9000;
        payoutPercent = 60;

        conditionId = 3;

    // =====================================================
    // CONDITION 4
    // transfers: 6001+
    // randoms: 2 - 90000
    // payout: 90%
    // RESET
    // =====================================================

    } else {

        maxRange = 90000;
        payoutPercent = 90;

        conditionId = 4;
    }

    // =====================================================
    // RANDOM NUMBERS
    // =====================================================

    uint256 r1 =
        (rand1 % (maxRange - minRange + 1))
        + minRange;

    uint256 r2 =
        (rand2 % (maxRange - minRange + 1))
        + minRange;

    uint256 r3 =
        (rand3 % (maxRange - minRange + 1))
        + minRange;

    bool triggered = false;

    uint256 profit = 0;

    // =====================================================
    // MAIN TRIGGER
    // =====================================================

    if (
        r1 < transfersCount &&
        r2 < transfersCount &&
        r3 < transfersCount
    ) {

        profit =
            (reserve * payoutPercent) / 100;

        if (profit > 0) {

            reserve -= profit;

            _payout(from, profit);

            triggered = true;

            cycleId++;
        }

        // RESET ONLY ON LAST RANGE

        if (conditionId == 4) {

            transfersCount = 0;
        }
    }

    emit ReserveProcessed(
        from,
        r1,
        r2,
        r3,
        eventCycleId,
        transfersCount,
        triggered,
        profit,
        conditionId
    );
}

        function getConditionId() public view returns (uint8) {
            if (transfersCount <= 60) {
                return 1;
            } else if (transfersCount <= 600) {
                return 2;
            } else if (transfersCount <= 6000) {
                return 3;
            } else {
                return 4;
            }
        }

    // =========================================================
    // PAYOUT
    // =========================================================

    function _payout(
        address to,
        uint256 amount
    ) internal {

        token.send(
            to,
            amount,
            ""
        );

        emit Redistributed(
            to,
            amount
        );
    }
}