pragma solidity 0.5.12;

// import "./IUniswapV2Router02.sol";
import "./BPool.sol";
import "./SafeMath.sol";


contract ProxyArbitrage {
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_ADDRESS = 0xa0f764E120459bca39dB7E57a0cE975a489aB4fa;
    uint internal constant MAX_SLIPPAGE_PERCENTAGE = 1000; // 10%

    event ArbitrageEvent(
        address tokenIn,
        address tokenOut,
        uint256 tokenAmountIn,
        uint spotPrice,
        uint256 maxPrice,
        uint256 minAmount,
        uint tokenAmountOut
    );

    constructor() public {
        // uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
        // Pool wETH/YFI : 0x1a690056370c63AF824050d2290D3160096661eE
        // Pool YFI / MYX: 0x32741a08c02cb0f72f7e3bd4bba4aeca455b34bc
        // Amount : 666000000000000000000 wETH
    }

    function arbitrage(address balancerPool1, uint256 wethAmount) public {
        // Have to approve "balancerPool1" and "balancerPool2" addresses for all token pairs involved
        BPool pool1 = BPool(balancerPool1);
        // BPool pool2 = BPool(balancerPool2);

        address[] memory tokens = pool1.getCurrentTokens();
        // Get current pair ratio
        uint spotPrice = pool1.getSpotPrice(tokens[0], tokens[1]);

        // Approve the pool from the ERC20 pairs for the ProxyArbitrage smart contract
        approveContract(tokens[0], balancerPool1, wethAmount);
        approveContract(tokens[1], balancerPool1, wethAmount);

        // Calculate maxPrice and minAmount based on `MAX_SPLIPPAGE_PERCENTAGE`
        uint256 maxPrice = SafeMath.add(spotPrice, calculatePercentage(spotPrice, MAX_SLIPPAGE_PERCENTAGE));
        uint256 minAmount = SafeMath.mul(SafeMath.div(wethAmount, maxPrice), 1 ether);

        // Trigger Swap
        (uint tokenAmountOut,) = pool1.swapExactAmountIn(tokens[0], wethAmount, tokens[1], minAmount, maxPrice);
        emit ArbitrageEvent(tokens[0], tokens[1], wethAmount, spotPrice, maxPrice, minAmount, tokenAmountOut);
    }

    function calculatePercentage(uint amount, uint percentage) pure public returns (uint256)  {
        return SafeMath.div(SafeMath.mul(amount, percentage), 10000);
    }

    function approveContract(address tokenAddress, address pool, uint amount) public {
        IERC20 token = IERC20(tokenAddress);

        if (token.allowance(address(this), pool) < amount) {
            token.approve(pool, 99999999999 ether);
        }
    }
}
