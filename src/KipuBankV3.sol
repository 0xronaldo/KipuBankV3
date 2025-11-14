// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Interfaces de Uniswap V2
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);

    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/**
 * Contrato KipuBankV3
 * Autor: Brayan Ronaldo Sanchez Mendoza
 * Desc: Banco descentralizado con integración Uniswap V2 y conversión automática a USDC
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    
    // ===== DECLARACIONES DE TIPOS =====
    struct TokenInfo {
        bool activo;
        uint8 decimales;
        bool requiresSwap; // true si necesita swap a USDC
    }

    // ===== ROLES =====
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant MANAGER = keccak256("MANAGER");
    
    // ===== VARIABLES CONSTANT =====
    uint8 private constant DECIMALES_USD = 6;
    address private constant ETH_ADDRESS = address(0);
    uint256 private constant SLIPPAGE_TOLERANCE = 300; // 3% en basis points
    
    // ===== INSTANCIAS INMUTABLES =====
    AggregatorV3Interface public immutable oracleETHUSD;
    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;
    address public immutable USDC;
    address public immutable WETH;
    address public immutable owner;
    
    // ===== VARIABLES DE ESTADO =====
    uint256 public bankCap; // Bank cap en USDC con 6 decimales
    bool public pausado;
    
    // ===== MAPPINGS =====
    // usuario => balance en USDC (normalizado a 6 decimales)
    mapping(address => uint256) public balances;
    
    // Tokens soportados para depósito
    mapping(address => TokenInfo) public tokens;
    
    // ===== EVENTOS =====
    event Deposito(address indexed usuario, address indexed tokenOriginal, uint256 montoOriginal, uint256 montoUSDC);
    event Retiro(address indexed usuario, uint256 montoUSDC);
    event SwapRealizado(address indexed tokenIn, uint256 amountIn, uint256 amountOutUSDC);
    event TokenAgregado(address indexed token, uint8 decimales);
    event BankCapActualizado(uint256 nuevoCap);
    
    // ===== ERRORES =====
    error BancoPausado();
    error MontoInvalido();
    error SaldoInsuficiente();
    error TokenNoSoportado();
    error LimiteSuperado();
    error TransferenciaFallida();
    error ParNoExiste();
    error SlippageExcedido();
    
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
    constructor(
        address _oracleETHUSD,
        address _uniswapRouter,
        address _uniswapFactory,
        address _usdc,
        uint256 _bankCap
    ) {
        owner = msg.sender;
        oracleETHUSD = AggregatorV3Interface(_oracleETHUSD);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = IUniswapV2Factory(_uniswapFactory);
        USDC = _usdc;
        WETH = uniswapRouter.WETH();
        bankCap = _bankCap;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN, msg.sender);
        _grantRole(MANAGER, msg.sender);
        
        // Configurar tokens soportados por defecto
        tokens[ETH_ADDRESS] = TokenInfo(true, 18, true); // ETH requiere swap
        tokens[USDC] = TokenInfo(true, 6, false); // USDC no requiere swap
        
        emit TokenAgregado(ETH_ADDRESS, 18);
        emit TokenAgregado(USDC, 6);
    }

    // ===== FUNCIONES PUBLICAS DE DEPOSITO =====
    
    /**
     * @notice Depositar ETH, convertir a USDC automáticamente
     */
    function depositarETH() external payable cuandoActivo montoValido(msg.value) nonReentrant {
        if (!tokens[ETH_ADDRESS].activo) revert TokenNoSoportado();
        
        // Realizar swap ETH -> USDC
        uint256 montoUSDC = _swapETHToUSDC(msg.value);
        
        // Verificar bank cap
        uint256 totalActual = _getTotalUSDCInBank();
        if (totalActual + montoUSDC > bankCap) revert LimiteSuperado();
        
        // Actualizar balance del usuario
        balances[msg.sender] += montoUSDC;
        
        emit Deposito(msg.sender, ETH_ADDRESS, msg.value, montoUSDC);
    }
    
    /**
     * @notice Depositar cualquier token ERC20 soportado
     */
    function depositarToken(address token, uint256 monto) 
        external 
        cuandoActivo 
        montoValido(monto) 
        nonReentrant
    {
        if (!tokens[token].activo) revert TokenNoSoportado();
        if (token == ETH_ADDRESS) revert TokenNoSoportado();
        
        // Transferir tokens del usuario al contrato
        bool exito = IERC20(token).transferFrom(msg.sender, address(this), monto);
        if (!exito) revert TransferenciaFallida();
        
        uint256 montoUSDC;
        
        if (token == USDC) {
            // Depósito directo de USDC
            montoUSDC = monto; // USDC ya tiene 6 decimales
        } else {
            // Realizar swap token -> USDC
            montoUSDC = _swapTokenToUSDC(token, monto);
        }
        
        // Verificar bank cap
        uint256 totalActual = _getTotalUSDCInBank();
        if (totalActual + montoUSDC > bankCap) revert LimiteSuperado();
        
        // Actualizar balance del usuario
        balances[msg.sender] += montoUSDC;
        
        emit Deposito(msg.sender, token, monto, montoUSDC);
    }

    // ===== FUNCIONES PUBLICAS DE RETIRO =====
    
    /**
     * @notice Retirar USDC directamente
     */
    function retirarUSDC(uint256 montoUSDC) external cuandoActivo montoValido(montoUSDC) nonReentrant {
        if (balances[msg.sender] < montoUSDC) revert SaldoInsuficiente();
        
        // Actualizar balance antes de transferir
        balances[msg.sender] -= montoUSDC;
        
        // Transferir USDC
        bool exito = IERC20(USDC).transfer(msg.sender, montoUSDC);
        if (!exito) revert TransferenciaFallida();
        
        emit Retiro(msg.sender, montoUSDC);
    }

    // ===== FUNCIONES INTERNAS DE SWAP =====
    
    /**
     * @notice Intercambiar ETH por USDC usando Uniswap V2
     */
    function _swapETHToUSDC(uint256 ethAmount) internal returns (uint256) {
        // Verificar que existe el par WETH/USDC
        address pair = uniswapFactory.getPair(WETH, USDC);
        if (pair == address(0)) revert ParNoExiste();
        
        // Calcular el monto mínimo de salida (con slippage)
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        
        uint[] memory amountsOut = uniswapRouter.getAmountsOut(ethAmount, path);
        uint256 amountOutMin = (amountsOut[1] * (10000 - SLIPPAGE_TOLERANCE)) / 10000;
        
        // Realizar el swap
        uint[] memory amounts = uniswapRouter.swapExactETHForTokens{value: ethAmount}(
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        );
        
        emit SwapRealizado(ETH_ADDRESS, ethAmount, amounts[1]);
        return amounts[1];
    }
    
    /**
     * @notice Intercambiar cualquier token por USDC usando Uniswap V2
     */
    function _swapTokenToUSDC(address token, uint256 amount) internal returns (uint256) {
        // Verificar que existe el par token/USDC
        address pair = uniswapFactory.getPair(token, USDC);
        if (pair == address(0)) revert ParNoExiste();
        
        // Aprobar el router para gastar tokens
        IERC20(token).approve(address(uniswapRouter), amount);
        
        // Calcular el monto mínimo de salida (con slippage)
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = USDC;
        
        uint[] memory amountsOut = uniswapRouter.getAmountsOut(amount, path);
        uint256 amountOutMin = (amountsOut[1] * (10000 - SLIPPAGE_TOLERANCE)) / 10000;
        
        // Realizar el swap
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amount,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        );
        
        emit SwapRealizado(token, amount, amounts[1]);
        return amounts[1];
    }

    // ===== FUNCIONES DE CONSULTA =====
    
    /**
     * @notice Obtener mi balance en USDC
     */
    function miBalance() external view returns (uint256) {
        return balances[msg.sender];
    }
    
    /**
     * @notice Obtener el total de USDC en el banco
     */
    function _getTotalUSDCInBank() internal view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }
    
    /**
     * @notice Obtener información de un token
     */
    function obtenerInfoToken(address token) external view returns (TokenInfo memory) {
        return tokens[token];
    }
    
    /**
     * @notice Estimar cuánto USDC se recibiría por un monto de token
     */
    function estimarSwapAUSDC(address token, uint256 monto) external view returns (uint256) {
        if (token == USDC) return monto;
        if (token == ETH_ADDRESS) token = WETH;
        
        address pair = uniswapFactory.getPair(token, USDC);
        if (pair == address(0)) return 0;
        
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = USDC;
        
        try uniswapRouter.getAmountsOut(monto, path) returns (uint[] memory amounts) {
            return amounts[1];
        } catch {
            return 0;
        }
    }

    // ===== FUNCIONES ADMINISTRATIVAS =====
    
    /**
     * @notice Agregar un nuevo token soportado
     */
    function agregarToken(address token, uint8 decimales) external onlyRole(ADMIN) {
        require(!tokens[token].activo, "Token ya existe");
        require(token != ETH_ADDRESS, "Use configurarETH()");
        
        // Verificar que existe par con USDC (excepto para USDC mismo)
        if (token != USDC) {
            address pair = uniswapFactory.getPair(token, USDC);
            require(pair != address(0), "Par no existe en Uniswap");
        }
        
        tokens[token] = TokenInfo(true, decimales, token != USDC);
        emit TokenAgregado(token, decimales);
    }
    
    /**
     * @notice Actualizar el bank cap
     */
    function actualizarBankCap(uint256 nuevoCap) external onlyRole(MANAGER) {
        bankCap = nuevoCap;
        emit BankCapActualizado(nuevoCap);
    }
    
    /**
     * @notice Pausar el banco
     */
    function pausar() external onlyRole(ADMIN) {
        pausado = true;
    }
    
    /**
     * @notice Despausar el banco
     */
    function despausar() external onlyRole(ADMIN) {
        pausado = false;
    }
    
    /**
     * @notice Función de emergencia para retirar tokens
     */
    function emergenciaRetirarToken(address token, uint256 monto) external onlyRole(ADMIN) {
        if (token == ETH_ADDRESS) {
            (bool exito, ) = msg.sender.call{value: monto}("");
            require(exito, "Transferencia fallida");
        } else {
            IERC20(token).transfer(msg.sender, monto);
        }
    }
    
    /**
     * @notice Recibir ETH directamente - delegamos a depositarETH
     */
    receive() external payable {
        if (msg.value > 0 && !pausado && tokens[ETH_ADDRESS].activo) {
            // Llamar internamente a la lógica de depósito ETH
            uint256 montoUSDC = _swapETHToUSDC(msg.value);
            uint256 totalActual = _getTotalUSDCInBank();
            require(totalActual + montoUSDC <= bankCap, "Limite superado");
            
            balances[msg.sender] += montoUSDC;
            emit Deposito(msg.sender, ETH_ADDRESS, msg.value, montoUSDC);
        }
    }
}