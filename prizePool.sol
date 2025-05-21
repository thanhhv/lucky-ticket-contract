// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PrizePool
 * @dev A contract that allows users to deposit tokens into a prize pool.
 * After a specified time, a random winner is selected to receive all tokens in the pool.
 */
contract PrizePool is Ownable, ReentrancyGuard {
    // Struct to store pool information
    struct Pool {
        IERC20 token;           // Token used for the pool
        string tokenName;       // Name of the token
        uint256 requiredAmount; // Required amount for each participant
        uint256 maxParticipants; // Maximum number of participants allowed
        uint256 endTime;        // Time when the pool will end
        uint256 totalAmount;    // Total amount of tokens in the pool
        address[] participants; // List of participants
        mapping(address => bool) hasParticipated; // Track if an address has participated
        bool isActive;          // Whether the pool is active
        bool isFinished;        // Whether the pool has finished
        address winner;         // Winner of the pool
    }

    // Current pool ID
    uint256 public currentPoolId;
    
    // Default maximum number of participants per pool
    uint256 public constant DEFAULT_MAX_PARTICIPANTS = 50;
    
    // Mapping from pool ID to Pool
    mapping(uint256 => Pool) public pools;
    
    // Events
    event PoolCreated(uint256 indexed poolId, address indexed tokenAddress, string tokenName, uint256 requiredAmount, uint256 maxParticipants, uint256 endTime);
    event Deposited(uint256 indexed poolId, address indexed participant, uint256 amount);
    event WinnerSelected(uint256 indexed poolId, address indexed winner, uint256 amount);
    event PrizeDistributed(uint256 indexed poolId, address indexed winner, uint256 amount);
    event PoolFinished(uint256 indexed poolId);

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Create a new prize pool
     * @param _token Address of the ERC20 token to be used
     * @param _tokenName Name of the token
     * @param _requiredAmount Required amount for each participant
     * @param _maxParticipants Maximum number of participants allowed
     * @param _duration Duration of the pool in seconds
     */
    function createPool(address _token, string memory _tokenName, uint256 _requiredAmount, uint256 _maxParticipants, uint256 _duration) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(bytes(_tokenName).length > 0, "Token name cannot be empty");
        require(_requiredAmount > 0, "Required amount must be greater than 0");
        require(_maxParticipants > 0, "Max participants must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        
        // Check if there's an active pool
        if (currentPoolId > 0) {
            Pool storage lastPool = pools[currentPoolId];
            require(!lastPool.isActive || lastPool.isFinished, "Previous pool is still active");
        }
        
        // Increment pool ID
        currentPoolId++;
        
        // Create new pool
        Pool storage newPool = pools[currentPoolId];
        newPool.token = IERC20(_token);
        newPool.tokenName = _tokenName;
        newPool.requiredAmount = _requiredAmount;
        newPool.maxParticipants = _maxParticipants;
        newPool.endTime = block.timestamp + _duration;
        newPool.isActive = true;
        newPool.isFinished = false;
        
        emit PoolCreated(currentPoolId, _token, _tokenName, _requiredAmount, _maxParticipants, newPool.endTime);
    }

    /**
     * @dev Deposit tokens into the current pool
     * @param _amount Amount of tokens to deposit
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(currentPoolId > 0, "No active pool");
        
        Pool storage pool = pools[currentPoolId];
        require(pool.isActive, "Pool is not active");
        require(!pool.isFinished, "Pool is already finished");
        require(block.timestamp < pool.endTime, "Pool has ended");
        require(!pool.hasParticipated[msg.sender], "Already participated");
        require(pool.participants.length < pool.maxParticipants, "Pool is full");
        require(_amount == pool.requiredAmount, "Amount must be exactly the required amount");
        
        // Transfer tokens from sender to contract
        require(pool.token.transferFrom(msg.sender, address(this), _amount), "Token transfer failed");
        
        // Update pool information
        pool.participants.push(msg.sender);
        pool.hasParticipated[msg.sender] = true;
        pool.totalAmount += _amount;
        
        emit Deposited(currentPoolId, msg.sender, _amount);
    }

    /**
     * @dev Select a winner for the current pool
     * Can only be called by the owner after the pool has ended
     */
    function selectWinner() external onlyOwner {
        require(currentPoolId > 0, "No active pool");
        
        Pool storage pool = pools[currentPoolId];
        require(pool.isActive, "Pool is not active");
        require(!pool.isFinished, "Pool is already finished");
        require(block.timestamp >= pool.endTime, "Pool has not ended yet");
        require(pool.participants.length > 0, "No participants");
        
        // Generate random index
        uint256 randomIndex = _getRandomNumber(pool.participants.length);
        
        // Select winner
        address winner = pool.participants[randomIndex];
        pool.winner = winner;
        
        emit WinnerSelected(currentPoolId, winner, pool.totalAmount);
        
        // Distribute prize
        _distributePrize();
    }

    /**
     * @dev Distribute prize to the winner
     * Internal function called by selectWinner
     */
    function _distributePrize() internal {
        Pool storage pool = pools[currentPoolId];
        require(pool.winner != address(0), "No winner selected");
        
        uint256 amount = pool.totalAmount;
        
        // Mark pool as finished
        pool.isActive = false;
        pool.isFinished = true;
        
        // Transfer tokens to winner
        require(pool.token.transfer(pool.winner, amount), "Token transfer failed");
        
        emit PrizeDistributed(currentPoolId, pool.winner, amount);
        emit PoolFinished(currentPoolId);
    }

    /**
     * @dev Get a random number between 0 and max-1
     * @param _max Maximum value (exclusive)
     * @return Random number
     */
    function _getRandomNumber(uint256 _max) internal view returns (uint256) {
        // This is a simple implementation and not secure for production
        // In production, use a verifiable random function (VRF) like Chainlink VRF
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            blockhash(block.number - 1),
            pools[currentPoolId].participants
        ))) % _max;
        
        return randomNumber;
    }

    /**
     * @dev Get the number of participants in a pool
     * @param _poolId Pool ID
     * @return Number of participants
     */
    function getParticipantsCount(uint256 _poolId) external view returns (uint256) {
        require(_poolId > 0 && _poolId <= currentPoolId, "Invalid pool ID");
        return pools[_poolId].participants.length;
    }

    /**
     * @dev Get participant at a specific index in a pool
     * @param _poolId Pool ID
     * @param _index Index of the participant
     * @return Participant address
     */
    function getParticipantAtIndex(uint256 _poolId, uint256 _index) external view returns (address) {
        require(_poolId > 0 && _poolId <= currentPoolId, "Invalid pool ID");
        require(_index < pools[_poolId].participants.length, "Invalid index");
        return pools[_poolId].participants[_index];
    }

    /**
     * @dev Check if an address has participated in a pool
     * @param _poolId Pool ID
     * @param _participant Participant address
     * @return Whether the address has participated
     */
    function hasParticipated(uint256 _poolId, address _participant) external view returns (bool) {
        require(_poolId > 0 && _poolId <= currentPoolId, "Invalid pool ID");
        return pools[_poolId].hasParticipated[_participant];
    }

    /**
     * @dev Get pool information
     * @param _poolId Pool ID
     * @return token Token address
     * @return tokenName Name of the token
     * @return requiredAmount Required amount for each participant
     * @return maxParticipants Maximum number of participants allowed
     * @return endTime End time of the pool
     * @return totalAmount Total amount of tokens in the pool
     * @return participantsCount Number of participants
     * @return isActive Whether the pool is active
     * @return isFinished Whether the pool has finished
     * @return winner Winner of the pool
     */
    function getPoolInfo(uint256 _poolId) external view returns (
        address token,
        string memory tokenName,
        uint256 requiredAmount,
        uint256 maxParticipants,
        uint256 endTime,
        uint256 totalAmount,
        uint256 participantsCount,
        bool isActive,
        bool isFinished,
        address winner
    ) {
        require(_poolId > 0 && _poolId <= currentPoolId, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        
        return (
            address(pool.token),
            pool.tokenName,
            pool.requiredAmount,
            pool.maxParticipants,
            pool.endTime,
            pool.totalAmount,
            pool.participants.length,
            pool.isActive,
            pool.isFinished,
            pool.winner
        );
    }

    /**
     * @dev Emergency function to recover tokens in case of an error
     * Can only be called by the owner
     * @param _token Token address
     * @param _amount Amount to recover
     */
    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 token = IERC20(_token);
        require(token.transfer(owner(), _amount), "Token transfer failed");
    }
}