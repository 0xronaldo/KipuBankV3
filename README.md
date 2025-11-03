# KipuBankV2

Autor: Brayan Sanchez  
Fecha: 2 de noviembre de 2025

## Descripcion

KipuBankV2 es un banco descentralizado que permite depositar y retirar ETH y tokens ERC-20. Implementa control de acceso con roles, normaliza todos los balances a 6 decimales para facilitar la contabilidad, y usa oráculos de Chainlink para obtener el precio de ETH en USD y controlar un límite máximo de depósitos.

## Se implemento : 
Control de Acceso

Declaraciones de Tipos

Instancia del Oráculo Chainlink

Variables Constant

Mappings anidados

Función de conversión de decimales y valores


## Componentes del Contrato

Declaraciones de Tipos
```solidity
struct TokenInfo {
    bool activo;
    uint8 decimales;
}
```

Instancia del Oraculo Chainlink
```solidity
AggregatorV3Interface public immutable oracleETHUSD;
```

Variables Constant
```solidity
uint8 private constant DECIMALES_USD = 6;
address private constant ETH_ADDRESS = address(0);
```

Mappings Anidados
```solidity
mapping(address => mapping(address => uint256)) public balances;
mapping(address => TokenInfo) public tokens;
```

Funcion de Conversion de Decimales
```solidity
function _normalizar(uint256 monto, uint8 decimalesOrigen) private pure returns (uint256)
```

Funcion de Conversión ETH a USD
```solidity
function convertirETHaUSD(uint256 montoETH) public view returns (uint256)
```

## Librerias que utilizo 
esto por que lo trabaje en local con foundry

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

## Contrato Desplegado
### (Ojo me equivoque de contrato en la plataforma pero aca esta el corregido que se desplego en Remix)
 
Network: Sepolia Testnet  
Address: 0xFFc86b7ddAde0Fd7f23a0D255F44D7011BFf085b  
Explorer: https://testnet.routescan.io/address/0xFFc86b7ddAde0Fd7f23a0D255F44D7011BFf085b/contract/11155111/code

## Requisitos Implementados

- Control de Acceso (AccessControl)
- Declaraciones de Tipos (struct TokenInfo)
- Instancia del Oráculo Chainlink (immutable)
- Variables Constant
- Mappings Anidados
- Función de conversión de decimales
- Función de conversión ETH a USD
- Eventos personalizados
- Errores custom
- Patrón Checks-Effects-Interactions
- Variables immutable

