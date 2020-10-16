// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

abstract contract KyberNetworkProxy {
  function removeAlerter ( address alerter ) virtual external;
  function enabled (  ) virtual external view returns ( bool );
  function pendingAdmin (  ) virtual external view returns ( address );
  function getOperators (  ) virtual external view returns ( address[] memory );
  function tradeWithHint ( address src, uint256 srcAmount, address dest, address destAddress, uint256 maxDestAmount, uint256 minConversionRate, address walletId, bytes calldata hint ) virtual external payable returns ( uint256 );
  function swapTokenToEther ( address token, uint256 srcAmount, uint256 minConversionRate ) virtual external returns ( uint256 );
  function withdrawToken ( address token, uint256 amount, address sendTo ) virtual external;
  function maxGasPrice (  ) virtual external view returns ( uint256 );
  function addAlerter ( address newAlerter ) virtual external;
  function kyberNetworkContract (  ) virtual external view returns ( address );
  function getUserCapInWei ( address user ) virtual external view returns ( uint256 );
  function swapTokenToToken ( address src, uint256 srcAmount, address dest, uint256 minConversionRate ) virtual external returns ( uint256 );
  function transferAdmin ( address newAdmin ) virtual external;
  function claimAdmin (  ) virtual external;
  function swapEtherToToken ( address token, uint256 minConversionRate ) virtual external payable returns ( uint256 );
  function transferAdminQuickly ( address newAdmin ) virtual external;
  function getAlerters (  ) virtual external view returns ( address[] memory );
  function getExpectedRate ( address src, address dest, uint256 srcQty ) virtual external view returns ( uint256 expectedRate, uint256 slippageRate );
  function getUserCapInTokenWei ( address user, address token ) virtual external view returns ( uint256 );
  function addOperator ( address newOperator ) virtual external;
  function setKyberNetworkContract ( address _kyberNetworkContract ) virtual external;
  function removeOperator ( address operator ) virtual external;
  function info ( bytes32 field ) virtual external view returns ( uint256 );
  function trade ( address src, uint256 srcAmount, address dest, address destAddress, uint256 maxDestAmount, uint256 minConversionRate, address walletId ) virtual external payable returns ( uint256 );
  function withdrawEther ( uint256 amount, address sendTo ) virtual external;
  function getBalance ( address token, address user ) virtual external view returns ( uint256 );
  function admin (  ) virtual external view returns ( address );
}
