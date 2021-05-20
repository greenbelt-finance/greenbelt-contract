// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";

import "./LhToken.sol";
import "./PrizeDistributor.sol";

// MasterChef is the master of LH. He can make Lh and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once LH is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. LHs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that LHs distribution occurs.
        uint256 accLhPerShare;   // Accumulated LHs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // Info of each land
    struct LandInfo {
        IBEP20 rewardToken; // Address of reward token contract
        uint256 rewardTokenAmount; // amount of reward token amount
        uint256 pid; // pool id
        uint256 subscriptionStartBlock;
        uint256 subscriptionEndBlock;
        uint256 totalBettingAmount;
        uint256 totalRewardAmount; // for calculate total land reward
        uint256 accRewardPerBetting;
        uint256 lastUpdatedBlock;
        bool isClaimable;
    }

    // The LH TOKEN!
    LhToken public lh;
    // Dev address.
    address public devaddr;
    // Deposit Fee address
    address public feeAddress;
    // LH tokens created per block.
    uint256 public lhPerBlock;
    // Bonus muliplier for early lh makers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LH mining starts.
    uint256 public startBlock;

    // Info of each land.
    LandInfo[] public landInfo;
    // Subscription Prize distributor 
    PrizeDistributor public prizeDistributor;
    // land subscription start Flag
    bool public subscriptionStartFlag;
    // subscription land start index
    uint256 public startLidIndex;
    // subscription land end index
    uint256 public endLidIndex;
    // subscription claimStatus
    uint public claimStatus = 0; // 0 : not claimable, 1 : claimable, 2 : no winner(draw)

    mapping (uint256 => mapping (address => uint256)) public landBettingAmount; // lid => address => landBettingAmount;
    mapping (uint256 => mapping (address => uint256)) public landRewardPaid; // lid => address => landBettingAmount;
    mapping (uint256 => mapping (address => uint256)) public landRewardAmount; // lid => address => landRewardAmount;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event SelectLand(address indexed user, uint256 indexed lid, uint256 amount);
    event UnSelectLand(address indexed user, uint256 indexed lid, uint256 amount);
    event ClaimLand(address indexed user, uint256 indexed lid, uint256 amount);

    constructor(
        LhToken _lh,
        PrizeDistributor _prizeDistributor,
        uint256 _lhPerBlock,
        uint256 _startBlock
    ) public {
        lh = _lh;
        prizeDistributor = _prizeDistributor;
        devaddr = msg.sender;
        feeAddress = msg.sender;
        lhPerBlock = _lhPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 3000, "add: invalid deposit fee basis points"); // max 30%
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLhPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's LH allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 3000, "set: invalid deposit fee basis points"); // max 30%
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending LHs on frontend.
    function pendingLh(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLhPerShare = pool.accLhPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 lhReward = multiplier.mul(lhPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLhPerShare = accLhPerShare.add(lhReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accLhPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 lhReward = multiplier.mul(lhPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        lh.mint(devaddr, lhReward.div(10));
        lh.mint(address(this), lhReward);
        pool.accLhPerShare = pool.accLhPerShare.add(lhReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for LH allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accLhPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeLhTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accLhPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accLhPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeLhTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            uint256 selectLandAmount = 0;
            if (subscriptionStartFlag) {
                for (uint i=startLidIndex; i<=endLidIndex; i++) {
                    if (landInfo[i].pid == _pid && landInfo[i].subscriptionEndBlock > block.number) {
                        selectLandAmount = selectLandAmount.add(landBettingAmount[i][msg.sender]);
                    }
                }   
                if (selectLandAmount > user.amount.sub(_amount)) {
                    uint256 over = selectLandAmount.sub(user.amount.sub(_amount));
                    for (uint i = startLidIndex; i <= endLidIndex; i++) {
                        if (over > 0 && landInfo[i].pid == _pid && landInfo[i].subscriptionEndBlock > block.number) {
                            if (landBettingAmount[i][msg.sender] >= over) {
                                unselectLand(i, over);
                                over = 0;
                            } else {
                                unselectLand(i, landBettingAmount[i][msg.sender]);
                                over = over.sub(landBettingAmount[i][msg.sender]);
                            }
                        }
                    }
                }
            }   
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLhPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // not update total rewardamount, user reward amount
        if (subscriptionStartFlag) {
            for (uint i=startLidIndex; i<=endLidIndex; i++) {
                if (landInfo[i].pid == _pid && landInfo[i].subscriptionEndBlock > block.number) {
                    landInfo[i].totalBettingAmount = landInfo[i].totalBettingAmount.sub(landBettingAmount[i][msg.sender]);
                    landBettingAmount[i][msg.sender] = 0;
                    // landRewardAmount[i][msg.sender] = 0;
                    landRewardPaid[i][msg.sender] = 0;
                }
            }
        }
       
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe lh transfer function, just in case if rounding error causes pool to not have enough LHs.
    function safeLhTransfer(address _to, uint256 _amount) internal {
        uint256 lhBal = lh.balanceOf(address(this));
        if (_amount > lhBal) {
            lh.transfer(_to, lhBal);
        } else {
            lh.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _lhPerBlock) public onlyOwner {
        massUpdatePools();
        lhPerBlock = _lhPerBlock;
    }

    /* ==========  LAND SUBSCRIPTION RESTRICTED FUNCTIONS  ========== */

    // add land by owner 
    // subscription lands pid must be same
    function addLand(uint256 _pid, IBEP20 _rewardToken, uint256 _subscriptionStartBlock, uint256 _subscriptionEndBlock) public onlyOwner {
        require(_subscriptionStartBlock > block.number && _subscriptionEndBlock > _subscriptionStartBlock, "AL1");
        
        landInfo.push(LandInfo({
            rewardToken: _rewardToken,
            rewardTokenAmount: 0,
            pid: _pid,
            subscriptionStartBlock: _subscriptionStartBlock,
            subscriptionEndBlock: _subscriptionEndBlock,
            totalBettingAmount: 0,
            totalRewardAmount: 0,
            accRewardPerBetting: 0,
            lastUpdatedBlock: _subscriptionStartBlock,
            isClaimable: false
        }));
    }

    // set land info by owner 
    // subscription lands pid must be same
    function setLand(uint256 _lid, uint256 _pid, uint256 _subscriptionStartBlock, uint256 _subscriptionEndBlock) public onlyOwner {
        require(landInfo[_lid].subscriptionEndBlock > block.number, "SL1");
        require(_subscriptionStartBlock > block.number && _subscriptionEndBlock > _subscriptionStartBlock, "SL2");

        landInfo[_lid].pid = _pid;
        landInfo[_lid].subscriptionStartBlock = _subscriptionStartBlock;
        landInfo[_lid].subscriptionEndBlock = _subscriptionEndBlock;
    }

    // set valid land ids by owner
    // must update id when add new lands 
    function setSubscriptionInfo(uint256 _startLidIndex, uint256 _endLidIndex) public onlyOwner {
        require(_startLidIndex <= _endLidIndex, "SS");
        require(_endLidIndex - _startLidIndex < 10, "SS2");
    
        subscriptionStartFlag = true;
        startLidIndex = _startLidIndex;
        endLidIndex = _endLidIndex;
    }

    // must call after land subscription finished and prize token sended to distributor contract
    function startClaim() public onlyOwner {
        uint256 minTotalRewardAmount = type(uint256).max;
        uint256 claimLandId = type(uint256).max;
        massUpdateLands();
        
        for (uint i=startLidIndex; i<=endLidIndex; i++) {
            require(!landInfo[i].isClaimable, "SC1");
            require(landInfo[i].subscriptionEndBlock < block.number, "SC2");
            if (i == startLidIndex) {
                // init
                minTotalRewardAmount = landInfo[i].totalRewardAmount;
                claimLandId = i;
                claimStatus = 1;
            } else if (minTotalRewardAmount > landInfo[i].totalRewardAmount) {
                // find less subscribed land
                minTotalRewardAmount = landInfo[i].totalRewardAmount;
                claimLandId = i;
                claimStatus = 1;
            } else if (minTotalRewardAmount == landInfo[i].totalRewardAmount) {
                // total reward amount same
                // compare totalBettingAmount
                if (landInfo[claimLandId].totalBettingAmount > landInfo[i].totalBettingAmount) {
                    claimLandId = i;
                    claimStatus = 1;
                } else if (landInfo[claimLandId].totalBettingAmount == landInfo[i].totalBettingAmount) {
                    // no one win
                    claimStatus = 2;
                }
            }
        }

        if (claimStatus == 1) {
            require(landInfo[claimLandId].rewardToken.balanceOf(address(prizeDistributor)) > 0, "SC");
            landInfo[claimLandId].isClaimable = true;
            landInfo[claimLandId].rewardTokenAmount = landInfo[claimLandId].rewardToken.balanceOf(address(prizeDistributor));
        }
        subscriptionStartFlag = false;
    }

    function endClaim() public onlyOwner {
        require(claimStatus == 1, "EC");
        for (uint i=startLidIndex; i<=endLidIndex; i++) {
            if (landInfo[i].isClaimable) {
                prizeDistributor.endPrize(landInfo[i].rewardToken, address(feeAddress));
                claimStatus = 0;
            }
        }
    }
   
    function updateSubscriptionStartFlag(bool _subscriptionStartFlag) public onlyOwner {
        subscriptionStartFlag = _subscriptionStartFlag;
    }

    function updateClaimStatus(uint _claimStatus) public onlyOwner {
        claimStatus = _claimStatus;
    }

    /* ==========  LAND VIEW FUNCTION  ========== */

    // Return reward multiplier over the given _from to _to block.
    function getLandMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function pendingReward(uint256 _lid, address _user) external view returns (uint256) {
        LandInfo storage land = landInfo[_lid];
        uint256 accRewardPerBetting = land.accRewardPerBetting;
        uint256 blockNum = block.number > land.subscriptionEndBlock ? land.subscriptionEndBlock : block.number;
        if (block.number > land.lastUpdatedBlock && land.totalBettingAmount != 0) {
            uint256 multiplier = getLandMultiplier(land.lastUpdatedBlock, blockNum);
            uint256 reward = multiplier.mul(land.totalBettingAmount);
            accRewardPerBetting = accRewardPerBetting.add(reward.mul(1e12).div(land.totalBettingAmount));
        }
        return landBettingAmount[_lid][_user].mul(accRewardPerBetting).div(1e12).sub(landRewardPaid[_lid][_user]);
    }
    
    /* ==========  LAND USER FUNCTION  ========== */

    function massUpdateLands() public {
        for (uint i=startLidIndex; i<=endLidIndex; i++) {
            updateLand(i);
        }
    }

    // Update land reward, betting variable to be up-to-date
    function updateLand(uint256 _lid) public {
        LandInfo storage land = landInfo[_lid];
        if (block.number <= land.lastUpdatedBlock) {
            return;
        }

        if (land.subscriptionEndBlock <= land.lastUpdatedBlock) {
            return;
        }

        uint256 blockNum = block.number > land.subscriptionEndBlock ? land.subscriptionEndBlock : block.number;
        
        if (land.totalBettingAmount == 0) {
            land.lastUpdatedBlock = blockNum;
            return;
        }

        // calculate reward
        uint256 multiplier = getLandMultiplier(land.lastUpdatedBlock, blockNum);
        uint256 reward = multiplier.mul(land.totalBettingAmount);
        land.accRewardPerBetting = land.accRewardPerBetting.add(reward.mul(1e12).div(land.totalBettingAmount));
        land.totalRewardAmount = land.totalRewardAmount.add(reward);
        land.lastUpdatedBlock = blockNum;
    }

    function selectLand(uint256 _lid, uint256 _amount) public {
        LandInfo storage land = landInfo[_lid];
        UserInfo storage user = userInfo[land.pid][msg.sender];
        require(land.subscriptionStartBlock < block.number && land.subscriptionEndBlock > block.number, "INVALID TIME");
        require(subscriptionStartFlag, "NOT STARTED");

        //update lands info
        massUpdateLands();

        //update user land reward info
        if(landBettingAmount[_lid][msg.sender] > 0) {
            uint256 pending = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12).sub(landRewardPaid[_lid][msg.sender]);
            if (pending > 0) { 
                landRewardAmount[_lid][msg.sender] = landRewardAmount[_lid][msg.sender].add(pending);
            }
        }
        
        //check select available and do it
        uint256 bettingAmount = 0;
        if(_amount > 0) {
            uint256 availableAmount = user.amount;
            for(uint i=startLidIndex; i<=endLidIndex; i++) {
               availableAmount = availableAmount.sub(landBettingAmount[i][msg.sender]);
            }
            if(availableAmount > 0) {
                availableAmount > _amount ? bettingAmount = _amount : bettingAmount = availableAmount;
                landBettingAmount[_lid][msg.sender] = landBettingAmount[_lid][msg.sender].add(bettingAmount);
                land.totalBettingAmount = land.totalBettingAmount.add(bettingAmount);
            }
        }

        landRewardPaid[_lid][msg.sender] = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12);

        emit SelectLand(msg.sender, _lid, bettingAmount);
    }

    function unselectLand(uint256 _lid, uint256 _amount) public {
        LandInfo storage land = landInfo[_lid];
        require(land.subscriptionStartBlock < block.number && land.subscriptionEndBlock > block.number, "INVALID TIME");
        require(landBettingAmount[_lid][msg.sender] >= _amount, "INVALID AMOUNT");
        require(subscriptionStartFlag, "NOT STARTED");

        massUpdateLands();

        //update user land reward info
        if(landBettingAmount[_lid][msg.sender] > 0) {
            uint256 pending = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12).sub(landRewardPaid[_lid][msg.sender]);
            if (pending > 0) { 
                landRewardAmount[_lid][msg.sender] = landRewardAmount[_lid][msg.sender].add(pending);
            }
        }

        //check unselect available and do it
        if(_amount > 0) {
           landBettingAmount[_lid][msg.sender] = landBettingAmount[_lid][msg.sender].sub(_amount);
           land.totalBettingAmount = land.totalBettingAmount.sub(_amount);
        }
        
        landRewardPaid[_lid][msg.sender] = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12);

        emit UnSelectLand(msg.sender, _lid, _amount);
    }

    function claimLand(uint256 _lid) public nonReentrant {
        LandInfo storage land = landInfo[_lid];
        require(claimStatus == 1 && land.isClaimable, "NOT CLAIMABLE");
        require(!subscriptionStartFlag, "SUBSCRIPTION NOT ENDED");

        if(landBettingAmount[_lid][msg.sender] > 0) {
            uint256 pending = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12).sub(landRewardPaid[_lid][msg.sender]);
            if (pending > 0) { 
                landRewardAmount[_lid][msg.sender] = landRewardAmount[_lid][msg.sender].add(pending);
            }
        }
        uint256 rewardAmount = 0;
        if (landRewardAmount[_lid][msg.sender] > 0) {
            rewardAmount = land.rewardTokenAmount.mul(landRewardAmount[_lid][msg.sender]).div(land.totalRewardAmount);
            if (rewardAmount > 0) {
                prizeDistributor.sendPrize(land.rewardToken, address(msg.sender), rewardAmount);
            }
            landRewardAmount[_lid][msg.sender] = 0;
        }
        landRewardPaid[_lid][msg.sender] = landBettingAmount[_lid][msg.sender].mul(land.accRewardPerBetting).div(1e12);
        emit ClaimLand(msg.sender, _lid, rewardAmount);
    }
}
