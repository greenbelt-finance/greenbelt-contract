pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";

contract PrizeDistributor is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    function sendPrize(IBEP20 _prizeToken, address _to, uint256 _amount) external onlyOwner returns (uint256) {
        require(_prizeToken.balanceOf(address(this)) >= _amount, "sendPrize: something wrong");
        _prizeToken.safeTransfer(address(_to), _amount);
    }

    function endPrize(IBEP20 _prizeToken, address _to) external onlyOwner {
        _prizeToken.safeTransfer(_to, _prizeToken.balanceOf(address(this)));
    }
}