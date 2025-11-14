// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Direcciones de contratos conocidos (Ethereum Mainnet)
        // Para testnet o otras redes, ajustar estas direcciones
        address oracleETHUSD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH/USD
        address uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
        address uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 Factory
        address usdc = 0xA0b86a33E6183c13f127b00003659e4e19E2f069; // USDC (Ethereum)
        
        // Para redes de prueba como Sepolia, usar estas direcciones:
        // address oracleETHUSD = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Sepolia ETH/USD
        // address uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Router en Sepolia
        // address uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Factory en Sepolia
        // address usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC en Sepolia
        
        uint256 bankCap = 1000000 * 10**6; // 1 millón USDC (6 decimales)
        
        vm.startBroadcast(deployerPrivateKey);
        
        KipuBankV3 kipuBankV3 = new KipuBankV3(
            oracleETHUSD,
            uniswapRouter,
            uniswapFactory,
            usdc,
            bankCap
        );
        
        console.log("KipuBankV3 desplegado en:", address(kipuBankV3));
        console.log("Owner:", kipuBankV3.owner());
        console.log("Bank Cap:", kipuBankV3.bankCap());
        console.log("USDC Address:", kipuBankV3.USDC());
        console.log("Uniswap Router:", address(kipuBankV3.uniswapRouter()));
        
        vm.stopBroadcast();
    }
}