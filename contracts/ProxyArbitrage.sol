pragma solidity 0.5.12;

import "./balancer/BPool.sol";
import "./libraries/SafeMath.sol";
import './uniswap/UniswapV2Library.sol';
import "./uniswap/IUniswapV2Router02.sol";


contract ProxyArbitrage {
    address payable private _owner;
    enum PoolType { BALANCER, UNISWAP, SUSHISWAP }

    // Uniswap Router addresses should be the same on mainnet and testnets
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    
    address internal constant SUSHISWAP_ROUTER_ADDRESS = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor() public {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
  
    // Ability to withdraw eth
    function withdrawEth() public onlyOwner {
        address(_owner).transfer(address(this).balance);
    }
   
    // Ability to withdraw any token
    function withdrawToken(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(address(_owner), token.balanceOf(address(this)));
    }

    /**
     * description: Main function to trigger arbitrage in many Uniswap/Balancer pools.
     *              This function requires ProxyArbitrage to hold wETH tokens
     */
    function arbitrage(address[] memory path, PoolType[] memory poolType, uint256 ethAmountIn, uint256 minAmountOut) public onlyOwner {
        require(path.length == poolType.length, 'Path and PoolType must be equal in length');
        require(minAmountOut > ethAmountIn, 'minAmountOut should be greater than amountIn.');
        
        IERC20 wethToken = IERC20(WETH_ADDRESS);
        uint256 startingEthBalance = wethToken.balanceOf(address(this));

        uint256 tokenInAmount;
        uint256 tokenOutAmount;
        address tokenOutAddress;
        address tokenInAddress;
                
        for (uint8 i = 0; i < path.length; i++) { 
            if (i == 0) {
                // On first iteration, the token traded is always wETH
                tokenInAddress = WETH_ADDRESS;
                tokenInAmount = ethAmountIn;
            } else {
                tokenInAddress = tokenOutAddress;
                tokenInAmount = tokenOutAmount;
            }
            
            if (poolType[i] == PoolType.BALANCER) {
                (tokenOutAmount, tokenOutAddress) = swapBalancerPool(path[i], tokenInAmount, tokenInAddress);
            } else if (poolType[i] == PoolType.UNISWAP) {
                (tokenOutAmount, tokenOutAddress) = swapUniswapPool(path[i], tokenInAmount, tokenInAddress, UNISWAP_ROUTER_ADDRESS);
            } else if (poolType[i] == PoolType.SUSHISWAP) {
                (tokenOutAmount, tokenOutAddress) = swapUniswapPool(path[i], tokenInAmount, tokenInAddress, SUSHISWAP_ROUTER_ADDRESS);
            } else{
                revert('Invalid pooltype');   
            }
        }


        require(tokenOutAddress == WETH_ADDRESS, 'Final token needs to be WETH');

        uint256 finalEthBalance = wethToken.balanceOf(address(this));
        require(finalEthBalance >= startingEthBalance, 'This transaction loses WETH');   
    }

    /**
     * description: Internal function that trigger trades in Balancer Pools
     * param address balancerPoolAddress: Balancer's pool address
     * param uint256 tokenAmountIn: Amount of token to trade in
     */
    function swapBalancerPool(address balancerPoolAddress, uint256 tokenAmountIn, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress) {
        BPool pool = BPool(balancerPoolAddress);

        // Retrieve the ERC20 token addresses for the `balancerPoolAddress`
        address[] memory tokens = pool.getCurrentTokens();

        tokenOutAddress = getTokenOutAddress(tokenInAddress, tokens[0], tokens[1]);

        // Find the current price for the pair
        uint256 spotPrice = pool.getSpotPrice(tokens[0], tokens[1]);

        // Approve the pool from the ERC20 pairs for the ProxyArbitrage smart contract
        approveContract(tokens[0], balancerPoolAddress, tokenAmountIn);
        approveContract(tokens[1], balancerPoolAddress, tokenAmountIn);

        // Calculate MaxPrice and MinAmountOut based on `MAX_SLIPPAGE_PERCENTAGE`
        uint256 maxPrice = SafeMath.mul(spotPrice, 2); //SafeMath.add(spotPrice, calculatePercentage(spotPrice, MAX_SLIPPAGE_PERCENTAGE));
        uint256 minAmountOut = 0;

        // Execute the exchange
        (tokenOutAmount,) = pool.swapExactAmountIn(tokenInAddress, tokenAmountIn, tokenOutAddress, minAmountOut, maxPrice);
    }

    function swapUniswapPool(address pairAddress, uint256 tokenAmountIn, address tokenInAddress, address routerAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress)  {
        IUniswapV2Pair pairContract = IUniswapV2Pair(pairAddress);
        address token0 = pairContract.token0();
        address token1 = pairContract.token1();
        
        tokenOutAddress = getTokenOutAddress(tokenInAddress, token0, token1);

        // Approve the pool from the ERC20 pairs for this smart contract
        approveContract(tokenInAddress, routerAddress, tokenAmountIn);
        approveContract(tokenOutAddress, routerAddress, tokenAmountIn);

        address[] memory orderedAddresses = new address[](2);
        orderedAddresses[0] = tokenInAddress;
        orderedAddresses[1] = tokenOutAddress;
        
        uint256 deadline = block.timestamp + 30; // 2 block deadline
        uint256 minAmountOut = 0; //calcUniswapMinAmountOut(pairContract, tokenAmountIn, tokenInAddress),
        
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
        router.swapExactTokensForTokens(
            tokenAmountIn,
            minAmountOut,
            orderedAddresses,
            address(this),
            deadline
        );

        IERC20 token = IERC20(tokenOutAddress);
        tokenOutAmount = token.balanceOf(address(this));
    }

    function getTokenOutAddress(address tokenInAddress, address token0, address token1) internal pure returns (address tokenOutAddress) {
        if (token0 == tokenInAddress) {
            tokenOutAddress = token1;
        } else {
            tokenOutAddress = token0;
        }     
    }

     /**
     * description: Approve the pool to move ERC20 tokens on behalf of the ProxyArbitrage contract
     * param address tokenAddress: ERC20 token address
     * param uint256 pool: Balancer or Uniswap pool
     * param uint amount: amount to transfer (ensure that the alloance is at least >= amount)
     */
    function approveContract(address tokenAddress, address spender, uint amount) internal {
        IERC20 token = IERC20(tokenAddress);

        if (token.allowance(address(this), spender) < amount) {
            token.approve(spender, 99999999999 ether);
        }
    }   

}

