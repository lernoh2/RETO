// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC777/ERC777.sol";


interface IVRFGenerator {
    function requestBatch() external;
    function consumeRandom() external returns (uint256);
    function queueSize() external view returns (uint256);
}

contract GarettoRedistributor_V10 is IERC777Recipient, ReentrancyGuard {

    address public owner;
    ERC777 public immutable token;
    IVRFGenerator public generator;
     // ===== RESERVES =====
    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public reserve3;
    uint256 public reserve4;
    uint256 public reserve5;
    uint256 public reserve6;

    // ===== STATE =====
    uint256 public transfersCount;
    uint256 public transfersCount1;
    uint256 public transfersCount2;
    uint256 public transfersCount3;
    uint256 public transfersCount4;
    uint256 public transfersCount5;
    uint256 public transfersCount6;

    uint256 public cycleId1;
    uint256 public cycleId2;
    uint256 public cycleId3;
    uint256 public cycleId4;
    uint256 public cycleId5;
    uint256 public cycleId6;

    // ===== EVENTS =====
    event Received(address indexed from, uint256 amount);
    event Redistributed(address indexed to, uint256 amount, uint8 reserveId);
    event ReserveProcessed(
    address indexed sender,
    uint8 indexed reserveId,

    uint256 r1,
    uint256 r2,
    uint256 r3,
    uint256 sum,
    uint256 cycleId,
    uint256 transfers,
    bool triggered,
    uint256 profit,
    uint8 reason 
);

    constructor(ERC777 _token, address _generator) {
        IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24)
            .setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

        owner = msg.sender;
        token = _token;
        generator = IVRFGenerator(_generator);
        cycleId1 = 1;
        cycleId2 = 1;
        cycleId3 = 1;
        cycleId4 = 1;
        cycleId5 = 1;
        cycleId6 = 1;
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
      

        // ===== SPLIT =====
        uint256 share = amount / 6;
        reserve1 += share;
        reserve2 += share;
        reserve3 += share;
        reserve4 += share;
        reserve5 += share;
        reserve6 += (amount - share * 5);
        
       
    uint256 base;

if (generator.queueSize() == 0) {
    generator.requestBatch();
    base = uint256(keccak256(abi.encode(block.prevrandao, from, amount, transfersCount)));
} else {
    base = generator.consumeRandom();
}
        _processReserve1(from, base);
        _processReserve2(from, base);
        _processReserve3(from, base);
        _processReserve4(from, base);
        _processReserve5(from, base);
        _processReserve6(from, base);
        
    }

  

    // ===== RESERVE 1 =====
   function _processReserve1(address from, uint256 base) internal {
    transfersCount1++;

     bytes32 seed = keccak256(abi.encode(base, reserve1));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 66 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 66 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 66 + 2;

  uint256 sum = r1 + r2 + r3;

    bool triggered = false;
    uint256 p = 0;
    uint8 reason = 0;

    if (sum == 88) {
        p = reserve1 * 90 / 100;
        reason = 1;
    
      } else if (r1 < transfersCount1 && r2 < transfersCount1 && r3 < transfersCount1) {
            p = reserve1 * 30 / 100;
            reason = 2;
        }

    if (p > 0) {
        reserve1 -= p;
        _payout(from, p, 1);
        triggered = true;
    }

   emit ReserveProcessed(
    from,
    1,
    r1,
    r2,
    r3,
    sum,
    cycleId1,
    transfersCount1,
    triggered,
    p,
    reason
);

    // ✅ RESET AFTER EMIT
    if (triggered) {
        transfersCount1 = 0;
        cycleId1++;
    }
   }


    // ===== RESERVE 2 =====
    function _processReserve2(address from, uint256 base) internal {
          transfersCount2++;
       
   
     bytes32 seed = keccak256(abi.encode(base, reserve2));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 669 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 669 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 669 + 2;

         uint256 sum = r1 + r2 + r3;

    bool triggered = false;
    uint256 p = 0;
    uint8 reason = 0;

       if (sum == 888) {
        p = reserve2 * 90 / 100;
        reason = 1;

    } else if (r1 < transfersCount2 && r2 < transfersCount2 && r3 < transfersCount2) {
            p = reserve2 * 30 / 100;
            reason = 2;
    }

    if (p > 0) {
        reserve2 -= p;
        _payout(from, p, 2);
        triggered = true;
    }

     emit ReserveProcessed(
    from,
    2,
    r1,
    r2,
    r3,
    sum,
    cycleId2,
    transfersCount2,
    triggered,
    p,
    reason
);

    if (triggered) {
        transfersCount2 = 0;
        cycleId2++;
    }
}

    // ===== RESERVE 3 =====
    function _processReserve3(address from, uint256 base) internal {
         transfersCount3++;
      
    bytes32 seed = keccak256(abi.encode(base, reserve3));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 6999 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 6999 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 6999 + 2;

     uint256 sum = r1 + r2 + r3;
       

        bool triggered = false;
        uint256 p = 0;
        uint8 reason = 0;

           if (sum == 8888) {
        p = reserve3 * 90 / 100;
        reason = 1;
   
    } else if (r1 < transfersCount3 && r2 < transfersCount3 && r3 < transfersCount3) {
            p = reserve3 * 30 / 100;
            reason = 2;
    }

    if (p > 0) {
        reserve3 -= p;
        _payout(from, p, 3);
        triggered = true;
    }

        emit ReserveProcessed(
    from,
    3,
    r1,
    r2,
    r3,
    sum,
    cycleId3,
    transfersCount3,
    triggered,
    p,
    reason
);


    // ✅ RESET AFTER EMIT
    if (triggered) {
        transfersCount3 = 0;
        cycleId3++;
    }
}

// ===== RESERVE 4 =====
    function _processReserve4(address from, uint256 base) internal {
         transfersCount4++;
      
     bytes32 seed = keccak256(abi.encode(base, reserve4));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 66999 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 66999 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 66999 + 2;
        uint256 sum = r1 + r2 + r3;
       

        bool triggered = false;
        uint256 p = 0;
        uint8 reason = 0;

           if (sum == 88888) {
        p = reserve4 * 90 / 100;
        reason = 1;
    
    } else if (r1 < transfersCount4 && r2 < transfersCount4 && r3 < transfersCount4) {
            p = reserve4 * 30 / 100;
            reason = 2;
    }

    if (p > 0) {
        reserve4 -= p;
        _payout(from, p, 4);
        triggered = true;
    }

          emit ReserveProcessed(
    from,
    4,
    r1,
    r2,
    r3,
    sum,
    cycleId4,
    transfersCount4,
    triggered,
    p,
    reason
);

    // ✅ RESET AFTER EMIT
    if (triggered) {
        transfersCount4 = 0;
        cycleId4++;
    }
}

// ===== RESERVE 5 =====
    function _processReserve5(address from, uint256 base) internal {
         transfersCount5++;
      
    bytes32 seed = keccak256(abi.encode(base, reserve5));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 669999 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 669999 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 669999 + 2;
        uint256 sum = r1 + r2 + r3;
       

        bool triggered = false;
        uint256 p = 0;
        uint8 reason = 0;

           if (sum == 888888) {
        p = reserve5 * 90 / 100;
        reason = 1;
 
    } else if (r1 < transfersCount5 && r2 < transfersCount5 && r3 < transfersCount5) {
            p = reserve5 * 30 / 100;
            reason = 2;
    }

    if (p > 0) {
        reserve5 -= p;
        _payout(from, p, 5);
        triggered = true;
    }

          emit ReserveProcessed(
    from,
    5,
    r1,
    r2,
    r3,
    sum,
    cycleId5,
    transfersCount5,
    triggered,
    p,
    reason
);

    // ✅ RESET AFTER EMIT
    if (triggered) {
        transfersCount5 = 0;
        cycleId5++;
    }
}

// ===== RESERVE 6 =====
    function _processReserve6(address from, uint256 base) internal {
         transfersCount6++;
      
    bytes32 seed = keccak256(abi.encode(base, reserve6));
    uint256 r1 = uint256(keccak256(abi.encode(seed, 1))) % 6699999 + 2;
    uint256 r2 = uint256(keccak256(abi.encode(seed, 2))) % 6699999 + 2;
    uint256 r3 = uint256(keccak256(abi.encode(seed, 3))) % 6699999 + 2;
        uint256 sum = r1 + r2 + r3;
       

        bool triggered = false;
        uint256 p = 0;
        uint8 reason = 0;

           if (sum == 8888888) {
        p = reserve6 * 90 / 100;
        reason = 1;
   
    } else if (r1 < transfersCount6 && r2 < transfersCount6 && r3 < transfersCount6) {
            p = reserve6 * 30 / 100;
            reason = 2;
    }

    if (p > 0) {
        reserve6 -= p;
        _payout(from, p, 6);
        triggered = true;
    }

          emit ReserveProcessed(
    from,
    6,
    r1,
    r2,
    r3,
    sum,
    cycleId6,
    transfersCount6,
    triggered,
    p,
    reason
);

    // ✅ RESET AFTER EMIT
    if (triggered) {
        transfersCount6 = 0;
        cycleId6++;
    }
}



    // ===== PAYOUT =====
    function _payout(address to, uint256 amount, uint8 reserveId) internal {
        token.send(to, amount, "");
        emit Redistributed(to, amount, reserveId);
    }
}
