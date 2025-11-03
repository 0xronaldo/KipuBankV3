// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * Contrato KipuBankV2
 *  autot: Brayan Ronaldo Sanchez Mendoza
 *  desc: Banco descentralizado con soporte multi-token y control basado en USD
 */
contract KipuBankV2 is AccessControl {
    
    // ===== DECLARACIONES DE TIPOS =====
    struct TokenInfo {
        bool activo;
        uint8 decimales;
    }

    // ===== ROLES =====
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant MANAGER = keccak256("MANAGER");
    
    // ===== VARIABLES CONSTANT =====
    uint8 private constant DECIMALES_USD = 6;
    address private constant ETH_ADDRESS = address(0);
    
    // ===== INSTANCIA DEL ORACULO CHAINLINK =====
    AggregatorV3Interface public immutable oracleETHUSD;
    
    // ===== VARIABLES IMMUTABLE =====
    address public immutable owner;
    
    // ===== VARIABLES DE ESTADO =====
    uint256 public limiteUSD; // Bank cap en USD con 6 decimales
    bool public pausado;
    
    // ===== MAPPINGS ANIDADOS =====
    // usuario => token => balance (normalizado a 6 decimales)
    mapping(address => mapping(address => uint256)) public balances;
    
    // Tokens soportados
    mapping(address => TokenInfo) public tokens;
    
    // ===== EVENTOS =====
    event Deposito(address indexed usuario, address indexed token, uint256 monto);
    event Retiro(address indexed usuario, address indexed token, uint256 monto);
    event TokenAgregado(address indexed token, uint8 decimales);
    event LimiteActualizado(uint256 nuevoLimite);
    
    // ===== ERRORES =====
    error BancoPausado();
    error MontoInvalido();
    error SaldoInsuficiente();
    error TokenNoSoportado();
    error LimiteSuperado();
    error TransferenciaFallida();
    
    // ===== MODIFICADORES =====
    modifier cuandoActivo() {
        if (pausado) revert BancoPausado();
        _;
    }
    
    modifier montoValido(uint256 monto) {
        if (monto == 0) revert MontoInvalido();
        _;
    }

    // ===== CONSTRUCTOR =====
    constructor(address _oracleETHUSD, uint256 _limiteUSD) {
        owner = msg.sender;
        oracleETHUSD = AggregatorV3Interface(_oracleETHUSD);
        limiteUSD = _limiteUSD;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
        _grantRole(MANAGER, msg.sender);
        
        // Agrego ETH como token soportado
        tokens[ETH_ADDRESS] = TokenInfo(true, 18);
        emit TokenAgregado(ETH_ADDRESS, 18);
    }

    // ===== FUNCIONES PUBLICAS =====
    
    /**
     * @notice Deposito ETH en mi cuenta
     */
    function depositarETH() external payable cuandoActivo montoValido(msg.value) {
        if (!tokens[ETH_ADDRESS].activo) revert TokenNoSoportado();
        
        // Verifico el limite en USD
        uint256 valorUSD = convertirETHaUSD(msg.value);
        uint256 totalActual = obtenerTotalDepositosUSD();
        if (totalActual + valorUSD > limiteUSD) revert LimiteSuperado();
        
        // Normalizo el monto a 6 decimales
        uint256 montoNormalizado = _normalizar(msg.value, 18);
        
        // Actualizo mi balance (Checks-Effects-Interactions)
        balances[msg.sender][ETH_ADDRESS] += montoNormalizado;
        
        emit Deposito(msg.sender, ETH_ADDRESS, msg.value);
    }
    
    /**
     * @notice Deposito tokens ERC20 en mi cuenta
     */
    function depositarToken(address token, uint256 monto) 
        external 
        cuandoActivo 
        montoValido(monto) 
    {
        if (!tokens[token].activo) revert TokenNoSoportado();
        if (token == ETH_ADDRESS) revert TokenNoSoportado();
        
        // Transfiero los tokens primero
        bool exito = IERC20(token).transferFrom(msg.sender, address(this), monto);
        if (!exito) revert TransferenciaFallida();
        
        // Normalizo y actualizo balance
        uint256 montoNormalizado = _normalizar(monto, tokens[token].decimales);
        balances[msg.sender][token] += montoNormalizado;
        
        emit Deposito(msg.sender, token, monto);
    }
    
    /**
     * @notice Retiro ETH de mi cuenta
     */
    function retirarETH(uint256 monto) external cuandoActivo montoValido(monto) {
        uint256 montoNormalizado = _normalizar(monto, 18);
        
        if (balances[msg.sender][ETH_ADDRESS] < montoNormalizado) {
            revert SaldoInsuficiente();
        }
        
        // Actualizo balance antes de transferir (Checks-Effects-Interactions)
        balances[msg.sender][ETH_ADDRESS] -= montoNormalizado;
        
        // Transfiero ETH
        (bool exito, ) = msg.sender.call{value: monto}("");
        if (!exito) revert TransferenciaFallida();
        
        emit Retiro(msg.sender, ETH_ADDRESS, monto);
    }
    
    /**
     * @notice Retiro tokens ERC20 de mi cuenta
     */
    function retirarToken(address token, uint256 monto) 
        external 
        cuandoActivo 
        montoValido(monto) 
    {
        if (!tokens[token].activo) revert TokenNoSoportado();
        if (token == ETH_ADDRESS) revert TokenNoSoportado();
        
        uint256 montoNormalizado = _normalizar(monto, tokens[token].decimales);
        
        if (balances[msg.sender][token] < montoNormalizado) {
            revert SaldoInsuficiente();
        }
        
        // Actualizo balance antes de transferir
        balances[msg.sender][token] -= montoNormalizado;
        
        // Transfiero tokens
        bool exito = IERC20(token).transfer(msg.sender, monto);
        if (!exito) revert TransferenciaFallida();
        
        emit Retiro(msg.sender, token, monto);
    }

    // ===== FUNCIONES DE CONVERSION DE DECIMALES =====
    
    /**
     * @notice Convierto cualquier monto a 6 decimales (standard USD)
     */
    function _normalizar(uint256 monto, uint8 decimalesOrigen) private pure returns (uint256) {
        if (decimalesOrigen == DECIMALES_USD) {
            return monto;
        } else if (decimalesOrigen > DECIMALES_USD) {
            return monto / (10 ** (decimalesOrigen - DECIMALES_USD));
        } else {
            return monto * (10 ** (DECIMALES_USD - decimalesOrigen));
        }
    }
    
    /**
     * @notice Obtengo el precio de ETH en USD desde Chainlink
     */
    function obtenerPrecioETH() public view returns (uint256) {
        (, int256 precio, , , ) = oracleETHUSD.latestRoundData();
        require(precio > 0, "Precio invalido");
        return uint256(precio); // Retorna con 8 decimales
    }
    
    /**
     * @notice Convierto ETH a USD
     */
    function convertirETHaUSD(uint256 montoETH) public view returns (uint256) {
        uint256 precioETH = obtenerPrecioETH(); // 8 decimales
        // montoETH (18 dec) * precioETH (8 dec) / 1e18 / 1e2 = USD (6 dec)
        return (montoETH * precioETH) / 1e20;
    }
    
    /**
     * @notice Obtengo el total de depositos en USD
     */
    function obtenerTotalDepositosUSD() public view returns (uint256) {
        // Solo cuento ETH para el limite
        uint256 totalETH = address(this).balance;
        return convertirETHaUSD(totalETH);
    }

    // ===== FUNCIONES DE CONSULTA =====
    
    /**
     * @notice Obtengo mi balance de un token específico
     */
    function miBalance(address token) external view returns (uint256) {
        return balances[msg.sender][token];
    }
    
    /**
     * @notice Obtengo el balance original (sin normalizar)
     */
    function miBalanceOriginal(address token) external view returns (uint256) {
        uint256 balanceNormalizado = balances[msg.sender][token];
        uint8 decimales = tokens[token].decimales;
        
        if (decimales == DECIMALES_USD) {
            return balanceNormalizado;
        } else if (decimales > DECIMALES_USD) {
            return balanceNormalizado * (10 ** (decimales - DECIMALES_USD));
        } else {
            return balanceNormalizado / (10 ** (DECIMALES_USD - decimales));
        }
    }

    // ===== FUNCIONES ADMINISTRATIVAS =====
    
    /**
     * @notice Agrego un nuevo token soportado
     */
    function agregarToken(address token, uint8 decimales) external onlyRole(ADMIN) {
        require(!tokens[token].activo, "Token ya existe");
        tokens[token] = TokenInfo(true, decimales);
        emit TokenAgregado(token, decimales);
    }
    
    /**
     * @notice Actualizo el limite del banco en USD
     */
    function actualizarLimite(uint256 nuevoLimite) external onlyRole(MANAGER) {
        limiteUSD = nuevoLimite;
        emit LimiteActualizado(nuevoLimite);
    }
    
    /**
     * @notice Pauso el banco
     */
    function pausar() external onlyRole(ADMIN) {
        pausado = true;
    }
    
    /**
     * @notice Despauso el banco
     */
    function despausar() external onlyRole(ADMIN) {
        pausado = false;
    }
    
    /**
     * @notice Recibo ETH directamente
     */
    receive() external payable {
        if (msg.value > 0 && !pausado && tokens[ETH_ADDRESS].activo) {
            uint256 valorUSD = convertirETHaUSD(msg.value);
            uint256 totalActual = obtenerTotalDepositosUSD();
            require(totalActual + valorUSD <= limiteUSD, "Limite superado");
            
            uint256 montoNormalizado = _normalizar(msg.value, 18);
            balances[msg.sender][ETH_ADDRESS] += montoNormalizado;
            emit Deposito(msg.sender, ETH_ADDRESS, msg.value);
        }
    }
}