// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {Pool} from "@chainlink/contracts-ccip/contracts/libraries/Pool.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {FinalityCodec} from "@chainlink/contracts-ccip/contracts/libraries/FinalityCodec.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    event SourcePoolDebug(
        address indexed sender,
        uint256 userInterestRate,
        bytes poolData
    );

    event DestinationPoolDebug(
        address indexed receiver,
        uint256 amount,
        bytes sourcePoolData,
        uint256 decodedInterestRate
    );

    constructor(IERC20 token, address, address rmnProxy, address router)
        TokenPool(token, 18, address(0), rmnProxy, router)
    {}

    /// @notice Burns tokens on the source chain.
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn,
        bytes4 requestedFinalityConfig,
        bytes calldata tokenArgs
    ) public virtual override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut,
        uint256 destTokenAmount) {
            _validateLockOrBurn(lockOrBurnIn, requestedFinalityConfig, tokenArgs, 0);

            uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

            bytes memory poolData = abi.encode(userInterestRate);

            emit SourcePoolDebug(
                lockOrBurnIn.originalSender,
                userInterestRate,
                poolData
            );  

            IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

            lockOrBurnOut = Pool.LockOrBurnOutV1({
                destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
                destPoolData: poolData
            });

            destTokenAmount = lockOrBurnIn.amount;
    }
        

    /// @notice Mints tokens on the destination chain.
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn,
        bytes4 requestedFinalityConfig
    ) public virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
        uint256 amount = releaseOrMintIn.sourceDenominatedAmount;

        _validateReleaseOrMint(releaseOrMintIn, amount, requestedFinalityConfig);

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        emit DestinationPoolDebug(releaseOrMintIn.receiver, amount, releaseOrMintIn.sourcePoolData, userInterestRate);

        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({
            destinationAmount: amount
        });
    }
}
