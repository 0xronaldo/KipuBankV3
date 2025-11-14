# KipuBankV3

Autor: Brayan Ronaldo Sanchez Mendoza  
Fecha: 13 de noviembre de 2025

## Descripcion


# Definiciones 


owner: Variable de solo lectura, no se puede cambiar
ADMIN: Rol que se puede otorgar/revocar a múltiples direcciones


KipuBankV3 implementa funcionalidades de intercambio automatico mediante Uniswap V2. El contrato anterior KipuBankV2 manejaba multiples tokens con normalizacion a 6 decimales pero esta version simplifica todo convirtiendo a USDC. Los usuarios depositan ETH o tokens ERC20 y el contrato ejecuta swaps usando el router de Uniswap V2 para obtener USDC que se almacena internamente. El mapping de balances cambio de ser anidado usuario=>token=>balance a simplemente usuario=>balance porque todo se convierte a USDC. Se agregaron interfaces IUniswapV2Router02 e IUniswapV2Factory para interactuar con el protocolo, ReentrancyGuard previene ataques de reentrada durante los swaps, el bank cap funciona directamente con USDC en lugar de calcular equivalencias USD dinamicamente. La funcion _swapETHToUSDC maneja conversiones de ETH mientras _swapTokenToUSDC procesa tokens ERC20, ambas verifican existencia de pares en Uniswap y aplican slippage tolerance del 3%. La variable SLIPPAGE_TOLERANCE se definio como constante 300 basis points para proteger contra deslizamiento excesivo durante intercambios. TokenInfo struct incorpora campo requiresSwap para identificar si un token necesita conversion o es USDC nativo.

El contrato anterior usaba obtenerPrecioETH() con Chainlink oracle para calcular valores USD pero ahora los precios se obtienen directamente de Uniswap mediante getAmountsOut. Las funciones retirarETH y retirarToken desaparecieron porque solo existe retirarUSDC, miBalanceOriginal tambien se elimino ya que no hay normalizacion. La funcion miBalance ahora no recibe parametros porque siempre retorna USDC. Variables immutable USDC y WETH se agregaron al constructor junto con uniswapRouter y uniswapFactory. La funcion depositarETH ejecuta _swapETHToUSDC internamente, depositarToken detecta si es USDC para deposito directo o ejecuta _swapTokenToUSDC para otros tokens. 

```solidity
function _swapETHToUSDC(uint256 ethAmount) internal returns (uint256)
function _swapTokenToUSDC(address token, uint256 amount) internal returns (uint256)
```

Ambas funciones verifican existencia del par con uniswapFactory.getPair(), calculan amountOutMin considerando slippage, ejecutan el swap correspondiente y emiten evento SwapRealizado. El modifier nonReentrant se aplica a depositarETH, depositarToken y retirarUSDC para prevenir ataques durante interacciones externas. La funcion agregarToken verifica que existe par en Uniswap antes de agregarlo como soportado, excepto para USDC que no requiere verificacion. Emergency function emergenciaRetirarToken permite al admin extraer tokens en caso necesario.

Constructor recibe cinco parametros incluyendo oracleETHUSD que sigue usandose aunque menos relevante, uniswapRouter para ejecutar swaps, uniswapFactory para verificar pares, direccion USDC y bankCap en unidades USDC. Direcciones Sepolia testnet: Router 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, Factory 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f, USDC 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, Oracle 0x694AA1769357215DE4FAC081bf1f309aDC325306. 

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

TokenInfo struct agrego campo requiresSwap booleano para distinguir tokens que necesitan conversion versus USDC directo. La normalizacion _normalizar() se elimino completamente porque ya no se manejan multiples denominaciones, todo queda en USDC 6 decimales. Bank cap cambio de limiteUSD variable con calculo dinamico basado en obtenerTotalDepositosUSD() a bankCap fijo en USDC que se compara directamente con _getTotalUSDCInBank(). 

Receive function mantiene logica similar pero llama _swapETHToUSDC en lugar de _normalizar. Eventos mantienen nombres pero Deposito ahora incluye montoOriginal y montoUSDC para rastrear conversion. Error ParNoExiste y SlippageExcedido se agregaron para manejo de fallas Uniswap. La funcion estimarSwapAUSDC permite preview de conversion antes de ejecutar transaccion, retorna 0 si par inexistente.

