// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";

// Mock contracts para testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint8 public decimals;
    string public name;
    string public symbol;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockUniswapRouter {
    address public WETH;
    MockERC20 public usdc;
    
    constructor(address _weth, address _usdc) {
        WETH = _weth;
        usdc = MockERC20(_usdc);
    }
    
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        // Mock: 1 ETH = 3000 USDC
        uint256 usdcAmount = (msg.value * 3000 * 10**6) / 10**18;
        usdc.mint(to, usdcAmount);
        
        amounts = new uint[](2);
        amounts[0] = msg.value;
        amounts[1] = usdcAmount;
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        MockERC20 tokenIn = MockERC20(path[0]);
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
        
        // Mock: cualquier token vale 1 USDC
        uint256 usdcAmount = amountIn;
        usdc.mint(to, usdcAmount);
        
        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = usdcAmount;
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[0] = amountIn;
        
        if (path[0] == WETH) {
            amounts[1] = (amountIn * 3000 * 10**6) / 10**18; // 1 ETH = 3000 USDC
        } else {
            amounts[1] = amountIn; // 1:1 ratio for other tokens
        }
    }
}

contract MockUniswapFactory {
    mapping(address => mapping(address => address)) public pairs;
    
    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}

contract MockChainlinkOracle {
    int256 public price = 300000000000; // $3000 with 8 decimals
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract KipuBankV3Test is Test {
    KipuBankV3 public kipuBank;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public testToken;
    MockUniswapRouter public router;
    MockUniswapFactory public factory;
    MockChainlinkOracle public oracle;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    function setUp() public {
        // Crear mocks
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        testToken = new MockERC20("Test Token", "TEST", 18);
        
        oracle = new MockChainlinkOracle();
        factory = new MockUniswapFactory();
        router = new MockUniswapRouter(address(weth), address(usdc));
        
        // Configurar pares en factory
        factory.setPair(address(weth), address(usdc), address(0x123));
        factory.setPair(address(testToken), address(usdc), address(0x456));
        
        // Desplegar KipuBankV3
        vm.prank(owner);
        kipuBank = new KipuBankV3(
            address(oracle),
            address(router),
            address(factory),
            address(usdc),
            1000000 * 10**6 // 1M USDC bank cap
        );
        
        // Dar ETH a usuarios para testing
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Dar tokens a usuarios para testing
        testToken.mint(user1, 1000 * 10**18);
        testToken.mint(user2, 1000 * 10**18);
    }
    
    function testDepositETH() public {
        vm.prank(user1);
        kipuBank.depositarETH{value: 1 ether}();
        
        uint256 balance = kipuBank.miBalance();
        assertTrue(balance > 0, "Balance should be greater than 0");
        
        // Con el mock, 1 ETH = 3000 USDC
        assertEq(balance, 3000 * 10**6, "Balance should be 3000 USDC");
    }
    
    function testDepositUSDC() public {
        // Dar USDC al usuario
        usdc.mint(user1, 1000 * 10**6);
        
        vm.startPrank(user1);
        usdc.approve(address(kipuBank), 1000 * 10**6);
        kipuBank.depositarToken(address(usdc), 1000 * 10**6);
        vm.stopPrank();
        
        uint256 balance = kipuBank.miBalance();
        assertEq(balance, 1000 * 10**6, "Balance should be 1000 USDC");
    }
    
    function testDepositERC20Token() public {
        vm.startPrank(user1);
        testToken.approve(address(kipuBank), 100 * 10**18);
        kipuBank.depositarToken(address(testToken), 100 * 10**18);
        vm.stopPrank();
        
        uint256 balance = kipuBank.miBalance();
        assertTrue(balance > 0, "Balance should be greater than 0");
    }
    
    function testWithdrawUSDC() public {
        // Primero depositar
        usdc.mint(user1, 1000 * 10**6);
        
        vm.startPrank(user1);
        usdc.approve(address(kipuBank), 1000 * 10**6);
        kipuBank.depositarToken(address(usdc), 1000 * 10**6);
        
        // Luego retirar
        kipuBank.retirarUSDC(500 * 10**6);
        vm.stopPrank();
        
        uint256 balance = kipuBank.miBalance();
        assertEq(balance, 500 * 10**6, "Balance should be 500 USDC");
        
        uint256 userUSDCBalance = usdc.balanceOf(user1);
        assertEq(userUSDCBalance, 500 * 10**6, "User should have 500 USDC");
    }
    
    function testBankCap() public {
        // Intentar depositar más del bank cap
        vm.expectRevert(KipuBankV3.LimiteSuperado.selector);
        vm.prank(user1);
        kipuBank.depositarETH{value: 500 ether}(); // 500 ETH = 1.5M USDC > 1M cap
    }
    
    function testAddToken() public {
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);
        factory.setPair(address(newToken), address(usdc), address(0x789));
        
        vm.prank(owner);
        kipuBank.agregarToken(address(newToken), 18);
        
        (bool activo, uint8 decimales, bool requiresSwap) = kipuBank.tokens(address(newToken));
        assertTrue(activo, "Token should be active");
        assertEq(decimales, 18, "Decimals should be 18");
        assertTrue(requiresSwap, "Token should require swap");
    }
    
    function testPauseUnpause() public {
        vm.prank(owner);
        kipuBank.pausar();
        
        vm.expectRevert(KipuBankV3.BancoPausado.selector);
        vm.prank(user1);
        kipuBank.depositarETH{value: 1 ether}();
        
        vm.prank(owner);
        kipuBank.despausar();
        
        // Ahora debería funcionar
        vm.prank(user1);
        kipuBank.depositarETH{value: 1 ether}();
        
        uint256 balance = kipuBank.miBalance();
        assertTrue(balance > 0, "Deposit should work after unpause");
    }
    
    function testEstimarSwap() public {
        uint256 estimacion = kipuBank.estimarSwapAUSDC(address(0), 1 ether);
        assertEq(estimacion, 3000 * 10**6, "Estimation should be 3000 USDC for 1 ETH");
        
        estimacion = kipuBank.estimarSwapAUSDC(address(usdc), 1000 * 10**6);
        assertEq(estimacion, 1000 * 10**6, "USDC estimation should be the same amount");
    }
    
    function testAccessControl() public {
        // Usuario normal no puede pausar
        vm.expectRevert();
        vm.prank(user1);
        kipuBank.pausar();
        
        // Usuario normal no puede agregar tokens
        vm.expectRevert();
        vm.prank(user1);
        kipuBank.agregarToken(address(testToken), 18);
    }
    
    function testReceiveFunction() public {
        vm.prank(user1);
        (bool success, ) = address(kipuBank).call{value: 1 ether}("");
        assertTrue(success, "Direct ETH transfer should work");
        
        uint256 balance = kipuBank.miBalance();
        assertEq(balance, 3000 * 10**6, "Balance should be 3000 USDC from direct transfer");
    }
}