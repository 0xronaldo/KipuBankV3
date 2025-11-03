// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/kipubankv2.sol";

contract DeployKipuBank is Script {
    function run() external {
        // Oracle ETH/USD en Sepolia
        address oracle = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        
        // Limite de 1,000,000 USD (con 6 decimales)
        uint256 limite = 1000000 * 10**6;
        
        vm.startBroadcast();
        
        KipuBankV2 banco = new KipuBankV2(oracle, limite);
        
        vm.stopBroadcast();
        
        console.log("KipuBankV2 desplegado en:", address(banco));
    }
}
