pragma solidity 0.5.12;

import "./balancer/BPool.sol";
import "./libraries/SafeMath.sol";
import './uniswap/UniswapV2Library.sol';
import "./uniswap/IUniswapV2Router02.sol";


contract Printer {
    address payable private _owner;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    enum PoolType { BALANCER, UNISWAP, SUSHISWAP, NONE }

    constructor() public {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "caller is not the owner");
        _;
    }

    // Ability to withdraw eth
    function withdrawEth() external onlyOwner {
        address(_owner).transfer(address(this).balance);
    }

    // Ability to withdraw any token
    function withdrawToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).transfer(
            address(_owner),
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    /**
     * description: Main function to trigger arbitrage in many Uniswap/Balancer pools.
     *              This function requires Printer to hold wETH tokens
     */
    function arbitrage(address[4] calldata path, PoolType[4] calldata poolType, uint256 ethAmountIn, uint256 estimateGasCost) external onlyOwner {
        uint256 startingEthBalance = IERC20(WETH_ADDRESS).balanceOf(address(this));
        uint256 currentAmount = ethAmountIn;
        address currentAddress = WETH_ADDRESS;
       
        for(uint i; i < (path.length-1); i++){
             (currentAmount, currentAddress) = handleSwap(poolType[i], path[i], currentAmount, currentAddress); 
        }

        require(currentAddress == WETH_ADDRESS, 'Final token needs to be WETH');
        require(IERC20(WETH_ADDRESS).balanceOf(address(this)) >= (startingEthBalance + estimateGasCost), 'This transaction loses WETH');
    }
    
    function handleSwap(PoolType poolType, address path, uint256 tokenInAmount, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress) {
        if (poolType == PoolType.UNISWAP) {
            (tokenOutAmount, tokenOutAddress) = swapUniswapPool(path, tokenInAmount, tokenInAddress, address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
        } else if (poolType == PoolType.BALANCER) {
            (tokenOutAmount, tokenOutAddress) = swapBalancerPool(path, tokenInAmount, tokenInAddress);
        } else if (poolType == PoolType.SUSHISWAP) {
            (tokenOutAmount, tokenOutAddress) = swapUniswapPool(path, tokenInAmount, tokenInAddress, address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F));
        } else{
            return (tokenInAmount, tokenInAddress);
        }
    }

    /**
     * description: Internal function that trigger trades in Balancer Pools
     * param address balancerPoolAddress: Balancer's pool address
     * param uint256 tokenAmountIn: Amount of token to trade in
     */
    function swapBalancerPool(address balancerPoolAddress, uint256 tokenAmountIn, address tokenInAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress) {
        // Retrieve the ERC20 token addresses for the `balancerPoolAddress`
        address[] memory tokens = BPool(balancerPoolAddress).getCurrentTokens();
        tokenOutAddress = getTokenOutAddress(tokenInAddress, tokens[0], tokens[1]);

        // Approve the pool from the ERC20 pairs for the Printer smart contract
        approveContract(tokens[0], balancerPoolAddress, tokenAmountIn);
        approveContract(tokens[1], balancerPoolAddress, tokenAmountIn);

        // Execute the exchange
        (tokenOutAmount,) = BPool(balancerPoolAddress).swapExactAmountIn(
            tokenInAddress, 
            tokenAmountIn, 
            tokenOutAddress, 
            0, 
            SafeMath.mul(BPool(balancerPoolAddress).getSpotPrice(tokens[0], tokens[1]), 2));
    }

    function swapUniswapPool(address pairAddress, uint256 tokenAmountIn, address tokenInAddress, address routerAddress) internal returns (uint256 tokenOutAmount, address tokenOutAddress)  {
        tokenOutAddress = getTokenOutAddress(
            tokenInAddress,
            IUniswapV2Pair(pairAddress).token0(),
            IUniswapV2Pair(pairAddress).token1());

        // Approve the pool from the ERC20 pairs for this smart contract
        approveContract(tokenInAddress, routerAddress, tokenAmountIn);
        approveContract(tokenOutAddress, routerAddress, tokenAmountIn);

        address[] memory orderedAddresses = new address[](2);
        orderedAddresses[0] = tokenInAddress;
        orderedAddresses[1] = tokenOutAddress;
        
        IUniswapV2Router02(routerAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmountIn,
            0,
            orderedAddresses,
            address(this),
            block.timestamp + 30
        );
        tokenOutAmount = IERC20(tokenOutAddress).balanceOf(address(this));
    }

    function getTokenOutAddress(address tokenInAddress, address token0, address token1) internal pure returns (address tokenOutAddress) {
        if (token0 == tokenInAddress) {
            tokenOutAddress = token1;
        } else {
            tokenOutAddress = token0;
        }
    }

     /**
     * description: Approve the pool to move ERC20 tokens on behalf of the Printer contract
     * param address tokenAddress: ERC20 token address
     * param uint256 spender: Balancer or Uniswap pool
     * param uint amount: amount to transfer (ensure that the alloance is at least >= amount)
     */
    function approveContract(address tokenAddress, address spender, uint amount) internal {
        if (IERC20(tokenAddress).allowance(address(this), spender) < amount) {
            IERC20(tokenAddress).approve(spender, 999999 ether);
        }
    }
}
