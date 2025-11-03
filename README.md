# KipuBankV2

Autor: Brayan Sanchez  
Fecha: 2 de noviembre de 2025

## Descripción

KipuBankV2 es una evolución del contrato KipuBank original que implementa control de acceso basado en roles mediante AccessControl de OpenZeppelin, soporte multi-token con contabilidad normalizada a 6 decimales, integración con oráculos de Chainlink para conversión de precios ETH/USD, y un sistema de bank cap dinámico. El contrato utiliza errores personalizados para optimización de gas, eventos detallados para observabilidad, y sigue el patrón Checks-Effects-Interactions para prevenir vulnerabilidades de reentrancy.

La arquitectura implementa mappings anidados para gestionar balances multi-token por usuario, variables immutable para ahorro de gas en lecturas repetidas, y funciones de conversión decimal para normalizar diferentes tokens al estándar USDC de 6 decimales. El sistema de roles permite separación de responsabilidades administrativas con ADMIN para gestión de tokens y pausa, y MANAGER para actualización de límites operacionales.

## Mejoras Implementadas

**Control de Acceso**  
Sistema de roles mediante AccessControl con tres niveles: DEFAULT_ADMIN_ROLE para control total del contrato, ADMIN para gestión de tokens soportados y pausa de emergencia, y MANAGER para actualización del bank cap. Permite múltiples administradores y separación granular de permisos.

**Soporte Multi-Token**  
Arquitectura que soporta ETH nativo mediante address(0) y múltiples tokens ERC-20. Sistema dinámico para agregar tokens con struct TokenInfo que almacena estado activo y decimales. Utiliza SafeERC20 de OpenZeppelin para transferencias seguras.

**Contabilidad Normalizada**  
Mapping anidado `mapping(address => mapping(address => uint256))` almacena balances de cada usuario por token. Normalización automática a 6 decimales (estándar USDC) mediante función `_normalizar()` para facilitar operaciones aritméticas entre tokens con diferentes decimales.

**Integración Chainlink**  
Instancia immutable de AggregatorV3Interface conectada al Data Feed ETH/USD de Chainlink en Sepolia (0x694AA1769357215DE4FAC081bf1f309aDC325306). Función `obtenerPrecioETH()` retorna precio con 8 decimales, `convertirETHaUSD()` convierte montos de 18 decimales a 6 decimales USD.

**Conversión de Decimales**  
Función privada `_normalizar(uint256 monto, uint8 decimalesOrigen)` convierte cualquier cantidad a 6 decimales. Si decimalesOrigen > 6, divide por 10^(diff). Si decimalesOrigen < 6, multiplica por 10^(diff). Función complementaria para denormalización al consultar balances originales.

**Eventos y Errores**  
Errores custom: BancoPausado, MontoInvalido, SaldoInsuficiente, TokenNoSoportado, LimiteSuperado, TransferenciaFallida. Eventos: Deposito(usuario, token, monto), Retiro(usuario, token, monto), TokenAgregado(token, decimales), LimiteActualizado(nuevoLimite).

**Seguridad**  
Patrón Checks-Effects-Interactions en todas las funciones de transferencia. Variables immutable (dueno, oracleETHUSD) y constant (DECIMALES_USD, ETH_ADDRESS) para optimización de gas. Sistema de pausa mediante flag booleano. Validación de precios del oráculo.

## Componentes Técnicos del Contrato

### Declaraciones de Tipos
```solidity
struct TokenInfo {
    bool activo;
    uint8 decimales;
}
```

### Instancia del Oráculo
```solidity
AggregatorV3Interface public immutable oracleETHUSD;
```

### Variables Constant
```solidity
uint8 private constant DECIMALES_USD = 6;
address private constant ETH_ADDRESS = address(0);
```

### Mappings Anidados
```solidity
mapping(address => mapping(address => uint256)) public balances;
```

### Función de Conversión
```solidity
function _normalizar(uint256 monto, uint8 decimalesOrigen) private pure returns (uint256)
function convertirETHaUSD(uint256 montoETH) public view returns (uint256)
```

## Pasos a Seguir

```bash
# Instalo las dependencias
npm install @openzeppelin/contracts @chainlink/contracts

# O con Foundry
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

## Despliegue

### Sepolia Testnet
```javascript
// Oráculo ETH/USD en Sepolia
const ORACLE = "0x694AA1769357215DE4FAC081bf1f309aDC325306";

// Límite: 1,000,000 USD (con 6 decimales)
const LIMITE = ethers.parseUnits("1000000", 6);

const KipuBankV2 = await ethers.getContractFactory("KipuBankV2");
const banco = await KipuBankV2.deploy(ORACLE, LIMITE);
```

### Comando
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

## 💻 Cómo Usar

### Deposito ETH
```javascript
// Deposito 1 ETH
await kipuBank.depositarETH({ value: ethers.parseEther("1.0") });
```

### Deposito Tokens
```javascript
// Primero apruebo
await token.approve(kipuBankAddress, monto);

// Luego deposito
await kipuBank.depositarToken(tokenAddress, monto);
```

### Retiro ETH
```javascript
await kipuBank.retirarETH(ethers.parseEther("0.5"));
```

### Consulto mi Balance
```javascript
const balance = await kipuBank.miBalance(tokenAddress);
const balanceOriginal = await kipuBank.miBalanceOriginal(tokenAddress);
```

### Administración
```javascript
// Agrego un token nuevo
await kipuBank.agregarToken(tokenAddress, 18);

// Actualizo el límite
await kipuBank.actualizarLimite(ethers.parseUnits("2000000", 6));

// Pauso en emergencia
await kipuBank.pausar();
```
