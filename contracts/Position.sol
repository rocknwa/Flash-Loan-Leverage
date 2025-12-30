// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

// Balancer
import {IVault, IERC20} from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import {IFlashLoanRecipient} from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";

// Uniswap V3 Router
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// Aave
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

interface IWETH {
    function deposit() external payable;
}

contract Position is IFlashLoanRecipient {
    // ERC20 Contracts
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Balancer Vault
    address constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Aave Pool
    address constant AAVE_POOL_ADDRESS =
        0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    uint256 constant AAVE_HEALTH_FACTOR_THRESHOLD = 1e18;

    // Uniswap Universal Router
    address constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 constant POOL_FEE = 500;

    // Contract Owner
    address public immutable owner;

    /// Params used for opening a long/short position
    struct OpenParams {
        address assetToSupply;
        address assetToBorrow;
        uint256 assetToBorrowAmount;
        uint256 initialCapital;
        uint256 expectedSwapAmount;
    }

    /// Params used for closing a long/short position
    struct CloseParams {
        address assetToWithdraw;
        address assetToRepay;
    }

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Position: Caller not owner");
        _;
    }

    /**
        Open a long/short position.
        @dev Can only be called by owner, will call Balancer's Vault contract.
        @param params Parameters required for opening a position.
        @custom:param assetToSupply. Address of token to supply.
        @custom:param assetToBorrow. Address of token to flash loan & borrow from Aave.
        @custom:param assetToBorrowAmount. Amount of asset to flash loan & borrow from Aave.
        @custom:param initialCapital. Amount of asset to use from the contract.
     */
    function openPosition(OpenParams memory params) external onlyOwner {
        bool isOpenPosition = true;
        bytes memory encodedParams = abi.encode(params);
        bytes memory data = abi.encode(isOpenPosition, encodedParams);

        // Token to flash loan, by default we are flash loaning 1 token.
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(params.assetToBorrow);

        // Flash loan amount.
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = params.assetToBorrowAmount;

        IVault(VAULT).flashLoan(this, tokens, amounts, data);
    }

    /**
        Close a long/short position.
        @dev Can only be called by owner. Will fetch the debt and 
             call Balancer's Vault contract.
        @param params Parameters required for closing a position.
        @custom:param assetToWithdraw. Address of token to withdraw from Aave.
        @custom:param assetToRepay. Address of token to flash loan & repay to Aave.
     */
    function closePosition(CloseParams memory params) external onlyOwner {
        bool isOpenPosition = false;
        bytes memory encodedParams = abi.encode(params);
        bytes memory data = abi.encode(isOpenPosition, encodedParams);

        // Token to flash loan, by default we are flash loaning 1 token.
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(params.assetToRepay);

        // We need to know what the debt amount is as we'll
        // use that as the flash amount.
        uint256 debt = getDebt(params.assetToRepay);

        // Flash loan amount.
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = debt;

        IVault(VAULT).flashLoan(this, tokens, amounts, data);
    }

    /**
        Handles logic after receiving the flash loan.
        @dev This function must only be called by Balancer's Vault.
        @param amounts. Amounts flash loaned.
        @param userData ABI encoded data from openPosition() or closePosition().
     */
    function receiveFlashLoan(
        IERC20[] memory,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    ) external {
        require(msg.sender == VAULT, "Position: Caller not Balancer Vault");

        (bool isOpenPosition, bytes memory encodedParams) = abi.decode(
            userData,
            (bool, bytes)
        );

        if (isOpenPosition) {
            OpenParams memory params = abi.decode(encodedParams, (OpenParams));
            open(params);

            // Repay flash loan
            IERC20(params.assetToBorrow).transfer(
                VAULT,
                params.assetToBorrowAmount
            );
        } else {
            CloseParams memory params = abi.decode(
                encodedParams,
                (CloseParams)
            );
            close(params, amounts[0]);

            // Repay flash loan
            IERC20(params.assetToRepay).transfer(VAULT, amounts[0]);
        }
    }

    /// INTERNAL FUNCTIONS

    /**
        Handles logic for opening a position. Swap > Supply > Borrow. 
        @param params Parameters required for opening a position.
        @custom:param assetToSupply. Address of token to supply.
        @custom:param assetToBorrow. Address of token to flash loan & borrow from Aave.
        @custom:param assetToBorrowAmount. Amount of asset to flash loan & borrow from Aave.
        @custom:param initialCapital. Amount of asset to use from the contract.
     */
    function open(OpenParams memory params) internal {
        // Swap on Uniswap V3
        uint256 assetToSupplyAmount = swap(
            params.assetToBorrow,
            params.assetToSupply,
            params.assetToBorrowAmount + params.initialCapital,
            params.expectedSwapAmount
        );

        // Supply Aave
        supply(params.assetToSupply, assetToSupplyAmount);

        // Borrow
        borrow(params.assetToBorrow, params.assetToBorrowAmount);

        // Check health factor
        require(
            getHealthFactor() > AAVE_HEALTH_FACTOR_THRESHOLD,
            "Position: Health factor below 0"
        );
    }

    /**
        Handles logic for closing a position. Repay > Withdraw > Swap. 
        @param params Parameters required for closing a position.
        @custom:param assetToWithdraw. Address of token to withdraw from Aave.
        @custom:param assetToRepay. Address of token to flash loan & repay to Aave.
        @param flashAmount The amount flash loaned.
        @dev The flashAmount is used as the minimum expected amount to be received
             from the swap.
     */
    function close(CloseParams memory params, uint256 flashAmount) internal {
        // Repay Aave borrow
        repay(params.assetToRepay);

        // Withdraw collateral from Aave
        uint256 amount = withdraw(params.assetToWithdraw);

        // Swap on Uniswap V3
        swap(params.assetToWithdraw, params.assetToRepay, amount, flashAmount);
    }

    /**
        Responsible for performing a swap on Uniswap V3.
        @param tokenIn Address of token to give.
        @param tokenOut Address of token to get.
        @param amountIn Amount of token to give.
        @param amountOutMin Minimum amount expected to be received from the swap.
        @return amountOut The amount received from the swap.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        // Approve token to swap
        IERC20(tokenIn).approve(ROUTER, amountIn);

        // Setup swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp + 20,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        // Perform swap
        amountOut = ISwapRouter(ROUTER).exactInputSingle(params);
    }

    /**
        Responsible for supplying to Aave.
        @param assetToSupply Address of token to supply.
        @param amount amount of token to supply.
     */
    function supply(address assetToSupply, uint256 amount) internal {
        IERC20(assetToSupply).approve(AAVE_POOL_ADDRESS, amount);
        IPool(AAVE_POOL_ADDRESS).supply(
            assetToSupply,
            amount,
            address(this),
            0
        );
    }

    /**
        Responsible for borrowing from Aave.
        @param assetToBorrow Address of token to borrow.
        @param amount amount of token to borrow.
     */
    function borrow(address assetToBorrow, uint256 amount) internal {
        IPool(AAVE_POOL_ADDRESS).borrow(
            assetToBorrow,
            amount,
            2,
            0,
            address(this)
        );
    }

    /**
        Responsible for repaying borrow from Aave.
        @param assetToRepay Address of token to repay.
     */
    function repay(address assetToRepay) internal {
        IERC20(assetToRepay).approve(AAVE_POOL_ADDRESS, type(uint256).max);
        IPool(AAVE_POOL_ADDRESS).repay(
            assetToRepay,
            type(uint256).max,
            2,
            address(this)
        );
    }

    /**
        Responsible for withdrawing supplied token from Aave.
        @param assetToWithdraw Address of token to withdraw.
        @return withdrawnAmount Amount of token withdrawn.
     */
    function withdraw(
        address assetToWithdraw
    ) internal returns (uint256 withdrawnAmount) {
        withdrawnAmount = IPool(AAVE_POOL_ADDRESS).withdraw(
            assetToWithdraw,
            type(uint256).max,
            address(this)
        );
    }

    /// EXTERNAL HELPER FUNCTIONS

    /**
        Responsible for supplying token to Aave.
        @notice Can be used to increase health factor of an existing position.
        @param assetToSupply Address of token to withdraw.
        @param amount Address of token to withdraw.
     */
    function supplyToAave(
        address assetToSupply,
        uint256 amount
    ) external onlyOwner {
        IERC20(assetToSupply).transferFrom(msg.sender, address(this), amount);
        IERC20(assetToSupply).approve(AAVE_POOL_ADDRESS, amount);
        IPool(AAVE_POOL_ADDRESS).supply(
            assetToSupply,
            amount,
            address(this),
            0
        );
    }

    /**
        Responsible for withdrawing token to Aave.
        @param assetToWithdraw Address of token to withdraw.
     */
    function withdrawFromAave(address assetToWithdraw) external onlyOwner {
        IPool(AAVE_POOL_ADDRESS).withdraw(
            assetToWithdraw,
            type(uint256).max,
            owner
        );
    }

    /**
        Responsible for withdrawing ETH from this contract.
        @dev Can only be called by owner of contract.
     */
    function withdrawETH() external onlyOwner {
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Position: Failed to send ETH");
    }

    /**
        Responsible for withdrawing ETH from this contract.
        @dev Can only be called by owner of contract.
        @param token Address of token to withdraw.
        @param amount Amount of token to withdraw.
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    /**
        Responsible for converting ETH to WETH.
        @dev Can only be called by owner of contract.
     */
    function getWETH() external payable onlyOwner {
        uint256 amount = msg.value;
        IWETH(WETH_ADDRESS).deposit{value: amount}();
    }

    /// VIEW FUNCTIONS

    /**
        Get contract's ERC20 token balance
        @param token Address of token.
     */
    function getTokenBalance(
        address token
    ) public view returns (uint256 balance) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
        Get contract's health factor on Aave
        @dev A health factor above 1 means the position is safe.
             See: https://aave.com/help/borrowing/liquidations
     */
    function getHealthFactor() public view returns (uint256) {
        (, , , , , uint256 healthFactor) = IPool(AAVE_POOL_ADDRESS)
            .getUserAccountData(address(this));
        return healthFactor;
    }

    /**
        Get contract's debt owed to Aave
        @param token Address of token.
     */
    function getDebt(address token) public view returns (uint256 debt) {
        DataTypes.ReserveData memory reserve = IPool(AAVE_POOL_ADDRESS)
            .getReserveData(token);

        return
            IERC20(reserve.variableDebtTokenAddress).balanceOf(address(this));
    }
}
