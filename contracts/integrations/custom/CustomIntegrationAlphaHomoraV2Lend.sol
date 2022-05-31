// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {ICurveMetaRegistry} from '../../interfaces/ICurveMetaRegistry.sol';
import {CustomIntegration} from './CustomIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';
import {ISafeBox} from '../../interfaces/external/alpha-homora-v2/ISafeBox.sol';
import {ISafeBoxETH} from '../../interfaces/external/alpha-homora-v2/ISafeBoxETH.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';

/**
 * @title CustomIntegrationAlphaHomoraV2Lend
 * @author adamb
 */
contract CustomIntegrationAlphaHomoraV2Lend is CustomIntegration {
    address constant SAFE_BOX_ETH_ADDRESS = 0xeEa3311250FE4c3268F8E684f7C87A82fF183Ec1;

    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;
    using ControllerLib for IBabController;

    /* ============ State Variables ============ */

    /* Add State variables here if any. Pass to the constructor */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) CustomIntegration('alpha_homora_v2_lend', _controller) {
        require(address(_controller) != address(0), 'invalid address');
    }

    /* =============== Internal Functions ============== */

    /**
     * Whether or not the data provided is valid
     *
     * hparam  _data                     Data provided
     * @return bool                      True if the data is correct
     */
    function _isValid(
        bytes memory _data
    ) internal view override returns (bool) {
      return _isValidSafeBox(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    }

    /**
     * Which address needs to be approved (IERC-20) for the input tokens.
     *
     * hparam  _data                     Data provided
     * hparam  _opType                   O for enter, 1 for exit
     * @return address                   Address to approve the tokens to
     */
    function _getSpender(
        bytes calldata _data,
        uint8 /* _opType */
    ) internal pure override returns (address) {
        return BytesLib.decodeOpDataAddressAssembly(_data, 12);
    }

    /**
     * The address of the IERC-20 token obtained after entering this operation
     *
     * @param  _token                     Address provided as param
     * @return address                    Address of the resulting lp token
     */
    function _getResultToken(address _token) internal pure override returns (address) {
        return _token;
    }

    /**
     * Return enter custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensOut          Amount of result tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to spender to enter
     * hparam  _maxAmountsIn             Amounts of tokens to send to spender
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getEnterCalldata(
        address, /* _strategy */
        bytes calldata _data,
        uint256, /* _resultTokensOut */
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
      require(_tokensIn.length == 1 && _maxAmountsIn.length == 1, 'Wrong amount of tokens provided');
      address safeBoxAddress = BytesLib.decodeOpDataAddressAssembly(_data, 12);

      if (_isETHSafeBox(safeBoxAddress)) {
        return (safeBoxAddress, _maxAmountsIn[0], abi.encodeWithSelector(ISafeBoxETH.deposit.selector));
      } else {
        return (safeBoxAddress, 0, abi.encodeWithSelector(ISafeBox.deposit.selector, _maxAmountsIn[0]));
      }
    }

    /**
     * Return exit custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensIn           Amount of result tokens to send
     * hparam  _tokensOut                Addresses of tokens to receive
     * hparam  _minAmountsOut            Amounts of input tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitCalldata(
        address, /* _strategy */
        bytes calldata _data,
        uint256 _resultTokensIn,
        address[] calldata, /* _tokensOut */
        uint256[] calldata /* _minAmountsOut */
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address safeBoxAddress = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        return (safeBoxAddress, 0, abi.encodeWithSelector(ISafeBoxETH.withdraw.selector, _resultTokensIn));
    }


    /* ============ External Functions ============ */

    /**
     * The tokens to be purchased by the strategy on enter according to the weights.
     * Weights must add up to 1e18 (100%)
     *
     * hparam  _data                      Address provided as param
     * @return _inputTokens               List of input tokens to buy
     * @return _inputWeights              List of weights for the tokens to buy
     */
    function getInputTokensAndWeights(
        bytes calldata _data
    ) external view override returns (address[] memory _inputTokens, uint256[] memory _inputWeights) {
        address safeBoxAddress = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        address[] memory inputTokens = new address[](1);
        uint256[] memory inputWeights = new uint256[](1);
        inputWeights[0] = 1e18; // 100%

        if (_isETHSafeBox(safeBoxAddress)) {
          inputTokens[0] = ISafeBoxETH(payable(safeBoxAddress)).weth();
        } else {
          inputTokens[0] = ISafeBox(safeBoxAddress).uToken();
        }

        return (inputTokens, inputWeights);
    }

    /**
     * The tokens to be received on exit.
     *
     * hparam  _strategy                  Strategy address
     * hparam  _data                      Bytes data
     * hparam  _liquidity                 Number with the amount of result tokens to exit
     * @return exitTokens                 List of output tokens to receive on exit
     * @return _minAmountsOut             List of min amounts for the output tokens to receive
     */
    function getOutputTokensAndMinAmountOut(
        address, /* _strategy */
        bytes calldata _data,
        uint256 _liquidity
    ) external view override returns (address[] memory exitTokens, uint256[] memory _minAmountsOut) {
        address safeBoxAddress = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        address[] memory outputTokens = new address[](1);
        uint256[] memory outputAmounts = new uint256[](1);
        outputTokens[0] = _isETHSafeBox(safeBoxAddress) ?
          ISafeBoxETH(payable(safeBoxAddress)).weth() :
          ISafeBox(safeBoxAddress).uToken();
        address cToken = ISafeBox(safeBoxAddress).cToken();
        uint exchangeRate = ICToken(cToken).exchangeRateStored();
        outputAmounts[0] = exchangeRate.preciseMul(_liquidity);

        return (outputTokens, outputAmounts);
    }

    /**
     * The price of the result token based on the asset received on enter
     *
     * hparam  _data                      Bytes data
     * hparam  _tokenDenominator          Token we receive the capital in
     * @return uint256                    Amount of result tokens to receive
     */
    function getPriceResultToken(
        bytes calldata _data,
        address _tokenDenominator
    ) external view override returns (uint256) {
        address safeBoxAddress = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        address underlyingToken = _isETHSafeBox(safeBoxAddress) ?
          ISafeBoxETH(payable(safeBoxAddress)).weth() :
          ISafeBox(safeBoxAddress).uToken();
        address cToken = ISafeBox(safeBoxAddress).cToken();
        uint exchangeRate = ICToken(cToken).exchangeRateStored();
        return _getPrice(underlyingToken, _tokenDenominator).preciseMul(exchangeRate);
    }

    /**
     * (OPTIONAL). Return pre action calldata
     *
     * hparam _strategy                  Address of the strategy
     * hparam  _asset                    Address param
     * hparam  _amount                   Amount
     * hparam  _customOp                 Type of Custom op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _strategy */
        address _asset,
        uint256 _amount,
        uint256 _customOp
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
      if (_isETHSafeBox(_asset)) {
        if (_customOp == 0) {// enter, need to unwrap WETH -> ETH
          return (ISafeBoxETH(payable(_asset)).weth(), 0, abi.encodeWithSelector(IWETH.withdraw.selector, _amount));
        } else {
          return (address(0), 0, bytes(''));
        }
      } else {
        return (address(0), 0, bytes(''));
      }
    }

    /**
     * (OPTIONAL) Return post action calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _asset                    Address param
     * hparam  _amount                   Amount
     * hparam  _customOp                 Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _strategy */
        address _asset,
        uint256 _amount,
        uint256 _customOp
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
      if (_isETHSafeBox(_asset)) {
        if (_customOp == 1) {// exit, need to wrap ETH -> WETH
          return (ISafeBoxETH(payable(_asset)).weth(), 0, abi.encodeWithSelector(IWETH.deposit.selector, _amount));
        } else {
          return (address(0), 0, bytes(''));
        }
      } else {
        return (address(0), 0, bytes(''));
      }
    }

    function _isValidSafeBox(address _safeBoxAddress) internal view returns (bool) {
      try ISafeBox(_safeBoxAddress).cToken() returns (address cToken) {
        return cToken != address(0);
      } catch (bytes memory) {
        return false;
      }
    }

    function _isETHSafeBox(address _safeBoxAddress) pure internal returns (bool) {
      return _safeBoxAddress == SAFE_BOX_ETH_ADDRESS;
    }
}
