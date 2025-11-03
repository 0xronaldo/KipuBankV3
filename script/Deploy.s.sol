// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/kipubankv2.sol";

contract DeployKipuBankV2 is Script {
    function run() external {
        // Oracle ETH/USD en Sepolia
        address oracleETHUSD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        
        // Bank cap: 1,000,000 USD (con 6 decimales)
        uint256 limiteUSD = 1_000_000 * 10**6;
        
        // Leer private key del entorno
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        KipuBankV2 banco = new KipuBankV2(oracleETHUSD, limiteUSD);
        
        console.log("KipuBankV2 desplegado en:", address(banco));
        console.log("Oracle ETH/USD:", oracleETHUSD);
        console.log("Limite USD:", limiteUSD);
        console.log("Owner:", banco.owner());
        
        vm.stopBroadcast();
    }
}
