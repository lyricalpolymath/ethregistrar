pragma solidity ^0.4.20;

import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is Ownable {
    uint constant public MIN_COMMITMENT_AGE = 1 hours;
    uint constant public MAX_COMMITMENT_AGE = 48 hours;
    uint constant public MIN_REGISTRATION_DURATION = 28 days;

    BaseRegistrar base;
    PriceOracle prices;

    mapping(bytes32=>uint) public commitments;

    event NameRegistered(string name, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, PriceOracle _prices) public {
        base = _base;
        prices = _prices;
    }

    function rentPrice(string name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(bytes(name));
        return prices.price(name, base.nameExpires(hash), duration);
    }

    function valid(string name) public view returns(bool) {
        return strlen(name) > 6;
    }

    function available(string name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(label);
    }

    function makeCommitment(string name, bytes32 secret) pure public returns(bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(label, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + MAX_COMMITMENT_AGE < now);
        commitments[commitment] = now;
    }

    function register(string name, address owner, uint duration, bytes32 secret) external payable {
        // Require a valid commitment
        bytes32 commitment = makeCommitment(name, secret);
        require(commitments[commitment] + MIN_COMMITMENT_AGE <= now);

        // If the commitment is too old, or the name is registered, stop
        if(commitments[commitment] + MAX_COMMITMENT_AGE < now || !available(name))  {
            msg.sender.transfer(msg.value);
            return;
        }
        delete(commitments[commitment]);

        uint cost = rentPrice(name, duration);
        require(duration >= MIN_REGISTRATION_DURATION);
        require(msg.value >= cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.register(label, owner, duration);
        emit NameRegistered(name, owner, cost, expires);

        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }
    }

    function renew(string name, uint duration) external payable {
        uint cost = rentPrice(name, duration);
        require(msg.value >= cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(label, duration);

        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }

        emit NameRenewed(name, cost, expires);
    }

    function setPriceOracle(PriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    /**
     * @dev Returns the length of a given string
     *
     * @param s The string to measure the length of
     * @return The length of the input string
     */
    function strlen(string s) internal pure returns (uint) {
        s; // Don't warn about unused variables
        // Starting here means the LSB will be the byte we care about
        uint ptr;
        uint end;
        assembly {
            ptr := add(s, 1)
            end := add(mload(s), ptr)
        }
        for (uint len = 0; ptr < end; len++) {
            uint8 b;
            assembly { b := and(mload(ptr), 0xFF) }
            if (b < 0x80) {
                ptr += 1;
            } else if (b < 0xE0) {
                ptr += 2;
            } else if (b < 0xF0) {
                ptr += 3;
            } else if (b < 0xF8) {
                ptr += 4;
            } else if (b < 0xFC) {
                ptr += 5;
            } else {
                ptr += 6;
            }
        }
        return len;
    }
}
