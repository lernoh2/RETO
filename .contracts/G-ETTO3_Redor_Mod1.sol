// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";

contract GarettoRedistributor_V8 is IERC777Recipient, ReentrancyGuard {

    address public owner;
    ERC777 public immutable token;

    // ===== RESERVES =====
    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public reserve3;

    // ===== STATE =====
    uint256 public transfersCount;
    uint256 public transfersCount1;
    uint256 public transfersCount2;
    uint256 public transfersCount3;

    uint256 public cycleId1;
    uint256 public cycleId2;
    uint256 public cycleId3;

    // ===== ENTROPY =====
    bytes32 private entropy1;
    bytes32 private entropy2;
    bytes32 private entropy3;

    // ===== EVENTS =====
    event Received(address indexed from, uint256 amount);
    event Redistributed(address indexed to, uint256 amount, uint8 reserveId);

    event B1RedistributionAttempt(
        address indexed sender,
        uint256 r1,
        uint256 r2,
        uint256 r3,
        uint256 sum,
        uint256 transfers,
        bool triggered,
        uint256 profit
    );

    event B2RedistributionAttempt(
        address indexed sender,
        uint256 r1,
        uint256 r2,
        uint256 r3,
        uint256 sum,
        uint256 transfers,
        bool triggered,
        uint256 profit
    );

    event B3RedistributionAttempt(
        address indexed sender,
        uint256 r1,
        uint256 r2,
        uint256 r3,
        uint256 sum1,
        uint256 sum2,
        uint256 transfers,
        bool triggered,
        uint256 profit
    );

    constructor(ERC777 _token) {
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

        owner = msg.sender;
        token = _token;
       
        cycleId1 = 1;
        cycleId2 = 1;
        cycleId3 = 1;
    }

    modifier onlyValidToken() {
        require(msg.sender == address(token), "Invalid token");
        _;
    }

    // ===== ENTRY =====
    function tokensReceived(
        address,
        address from,
        address,
        uint256 amount,
        bytes calldata,
        bytes calldata
    ) external override onlyValidToken nonReentrant {

        require(from != address(0), "Invalid sender");

        emit Received(from, amount);
          transfersCount++;
        // ===== ENTROPY =====
        entropy1 = keccak256(abi.encodePacked(entropy1, from, amount, block.prevrandao, blockhash(block.number-1), cycleId1));
        entropy2 = keccak256(abi.encodePacked(entropy2, from, amount, block.prevrandao, blockhash(block.number-1), cycleId2));
        entropy3 = keccak256(abi.encodePacked(entropy3, from, amount, block.prevrandao, blockhash(block.number-1), cycleId3));

        // ===== SPLIT =====
        uint256 share = amount / 3;
        reserve1 += share;
        reserve2 += share;
        reserve3 += (amount - share * 2);

        _processReserve1(from, amount);
        _processReserve2(from, amount);
        _processReserve3(from, amount);
        
    }

    // ===== RANDOM CORE =====
    function _rand(
        bytes32 e,
        uint256 salt,
        address from,
        uint256 amount,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 c1,
        uint256 c2,
        uint256 c3
    ) internal view returns (uint256) {

        return uint256(
            keccak256(
                abi.encodePacked(
                    e,
                    salt,
                    from,
                    amount,
                    t1,
                    t2,
                    t3,
                    gasleft(),
                    c1,
                    c2,
                    c3,
                    block.prevrandao,
                    blockhash(block.number - 1)
                )
            )
        );
    }

    // ===== RESERVE 1 =====
    function _processReserve1(address from, uint256 amount) internal {
          
        transfersCount1++;
       
        uint256 r1 = _rand(entropy1, 1, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 66 + 2;
        uint256 r2 = _rand(entropy1, 2, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 66 + 2;
        uint256 r3 = _rand(entropy1, 3, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 66 + 2;

        uint256 sum = r1 + r2 + r3;

        bool triggered = false;
        uint256 p = 0;

        if (sum == 88) {
            p = reserve1 * 90 / 100;
        } else if (transfersCount1 < 30 && sum < 41 && sum % 2 == 1) {
            p = reserve1 * 60 / 100;
        } else if (transfersCount1 > 30 && sum > 161 && sum % 2 == 0) {
            p = reserve1 * 30 / 100;
        }

        if (p > 0) {
            reserve1 -= p;
            _payout(from, p, 1);
            triggered = true;

            transfersCount1 = 0;
            cycleId1++;
        }

        emit B1RedistributionAttempt(from, r1, r2, r3, sum, transfersCount1, triggered, p);
    }

    // ===== RESERVE 2 =====
    function _processReserve2(address from, uint256 amount) internal {
          transfersCount2++;
       
        uint256 r1 = _rand(entropy2, 11, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 669 + 2;
        uint256 r2 = _rand(entropy2, 22, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 669 + 2;
        uint256 r3 = _rand(entropy2, 33, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 669 + 2;

        uint256 sum = r1 + r2 + r3;

        bool triggered = false;
        uint256 p = 0;

         if (sum == 888) {
            p = reserve1 * 90 / 100;
        } else if (transfersCount2 < 300 && sum < 300 && sum % 2 == 1) {
            p = reserve1 * 60 / 100;
        } else if (transfersCount2 > 300 && sum > 1800 && sum % 2 == 0) {
            p = reserve1 * 30 / 100;
        }

        if (p > 0) {
            reserve2 -= p;
            _payout(from, p, 2);
            triggered = true;

            transfersCount2 = 0;
            cycleId2++;
        }

        emit B2RedistributionAttempt(from, r1, r2, r3, sum, transfersCount2, triggered, p);
    }

    // ===== RESERVE 3 =====
    function _processReserve3(address from, uint256 amount) internal {
         transfersCount3++;
        uint256 r1 = _rand(entropy3, 1111, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 6669 + 2;
        uint256 r2 = _rand(entropy3, 2222, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 6669 + 2;
        uint256 r3 = _rand(entropy3, 3333, from, amount, transfersCount1, transfersCount2, transfersCount3, cycleId1, cycleId2, cycleId3) % 6669 + 2;

        uint256 sum2 = r1 + r2 + r3;
        uint256 sum1 = sum2 + transfersCount3;

        bool triggered = false;
        uint256 p = 0;

        if (sum1 == 10000) {
            p = reserve3 * 90 / 100;
        } else if (sum2 == 10000) {
            p = reserve3 * 60 / 100;
        } else if (r1 < transfersCount3 && r2 < transfersCount3 && r3 < transfersCount3) {
            p = reserve3 * 30 / 100;
        }

        if (p > 0) {
            reserve3 -= p;
            _payout(from, p, 3);
            triggered = true;

            transfersCount3 = 0;
            cycleId3++;
        }

        emit B3RedistributionAttempt(from, r1, r2, r3, sum1, sum2, transfersCount3, triggered, p);
    }

    // ===== PAYOUT =====
    function _payout(address to, uint256 amount, uint8 reserveId) internal {
        token.send(to, amount, "");
        emit Redistributed(to, amount, reserveId);
    }
}
