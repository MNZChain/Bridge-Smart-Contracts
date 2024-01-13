//SPDX-License-Identifier: MIT
pragma solidity 0.8.17; 

interface ERC20Essential 
{

    function balanceOf(address user) external view returns(uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);

}


//USDT contract in Ethereum does not follow ERC20 standard so it needs different interface
interface usdtContract
{
    function transferFrom(address _from, address _to, uint256 _amount) external;
}




//*******************************************************************//
//------------------ Contract to Manage Ownership -------------------//
//*******************************************************************//
contract owned
{
    address public owner;
    address internal newOwner;
    mapping(address => bool) public signer;

    event OwnershipTransferred(address indexed _from, address indexed _to);
    event SignerUpdated(address indexed signer, bool indexed status);

    constructor() {
        owner = msg.sender;
        //owner does not become signer automatically.
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    modifier onlySigner {
        require(signer[msg.sender], 'caller must be signer');
        _;
    }


    function changeSigner(address _signer, bool _status) public onlyOwner {
        signer[_signer] = _status;
        emit SignerUpdated(_signer, _status);
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    //the reason for this flow is to protect owners from sending ownership to unintended address due to human error
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}



    
//****************************************************************************//
//---------------------        MAIN CODE STARTS HERE     ---------------------//
//****************************************************************************//
    
contract Bridge is owned {
    
    uint256 public orderID;
    uint256 public exraCoinRewards;   // if we give users extra coins to cover gas cost of some initial transactions.

    uint256 public batchThreshold = 50;
    
    

    // This generates a public event of coin received by contract
    event CoinIn(uint256 indexed orderID, address indexed user, uint256 value, address outputCurrency);
    event CoinOut(uint256 indexed orderID, address indexed user, uint256 value);
    event CoinOutFailed(uint256 indexed orderID, address indexed user, uint256 value);
    event TokenIn(uint256 indexed orderID, address indexed tokenAddress, address indexed user, uint256 value, uint256 chainID, address outputCurrency);
    event TokenOut(uint256 indexed orderID, address indexed tokenAddress, address indexed user, uint256 value, uint256 chainID);
    event TokenOutFailed(uint256 indexed orderID, address indexed tokenAddress, address indexed user, uint256 value, uint256 chainID);

   

    
    receive () external payable {
        //nothing happens for incoming fund
    }
    
    function coinIn(address outputCurrency) external payable returns(bool){
        orderID++;
        payable(owner).transfer(msg.value);     //send fund to owner
        emit CoinIn(orderID, msg.sender, msg.value, outputCurrency);
        return true;
    }
    
    function batchCoinOut(address[] memory users, uint256[] memory amounts, uint256[] memory _orderIDs) external onlySigner returns(bool){
        require(users.length == amounts.length && users.length == _orderIDs.length, "Data lengths don't match");
        require(users.length < batchThreshold, "greater than batch threshold");
        for(uint8 index = 0; index < users.length; index++){
            coinOut(users[index], amounts[index], _orderIDs[index]);
        }
        return true;
    }

    function coinOut(address user, uint256 amount, uint256 _orderID) public onlySigner returns(bool){
        
            payable(user).transfer(amount);
            emit CoinOut(_orderID, user, amount);
        
        return true;
    }
    
    
    function tokenIn(address tokenAddress, uint256 tokenAmount, uint256 chainID, address outputCurrency) external returns(bool){
        orderID++;
        //fund will go to the owner
        if(tokenAddress == address(0xdAC17F958D2ee523a2206206994597C13D831ec7)){
            //There should be different interface for the USDT Ethereum contract
            usdtContract(tokenAddress).transferFrom(msg.sender, owner, tokenAmount);
        }else{
            ERC20Essential(tokenAddress).transferFrom(msg.sender, owner, tokenAmount);
        }
        emit TokenIn(orderID, tokenAddress, msg.sender, tokenAmount, chainID, outputCurrency);
        return true;
    }
    
    function batchTokenOut(address[] memory tokenAddresses, address[] memory users, uint256[] memory tokenAmounts, uint256[] memory _orderIDs, uint256[] memory chainIDs) onlySigner external returns (bool){
        require(tokenAddresses.length == users.length && tokenAddresses.length == tokenAmounts.length && tokenAddresses.length == _orderIDs.length && tokenAddresses.length == chainIDs.length, "Data length don't match");
        require(tokenAddresses.length < batchThreshold, "greater than batch threshold");
        
        for(uint256 index = 0; index < tokenAddresses.length; index++){
            tokenOut(tokenAddresses[index], users[index], tokenAmounts[index], _orderIDs[index], chainIDs[index]);
        }
        return true;
    }

    function tokenOut(address tokenAddress, address user, uint256 tokenAmount, uint256 _orderID, uint256 chainID) public onlySigner returns(bool){
       
            ERC20Essential(tokenAddress).transfer(user, tokenAmount);

            if(exraCoinRewards > 0 && address(this).balance >= exraCoinRewards){
                payable(user).transfer(exraCoinRewards);
            }
            emit TokenOut(_orderID, tokenAddress, user, tokenAmount, chainID);
        
        return true;
    }


    function setExraCoinsRewards(uint256 _exraCoinRewards) external onlyOwner returns( string memory){
        exraCoinRewards = _exraCoinRewards;
        return "Extra coins rewards updated";
    }

    function setBatchThreshold(uint256 _value) external onlyOwner returns(uint256 newValue){
        require(_value > 0, "zero value given");
        batchThreshold = _value;
        newValue = batchThreshold;
    }

}
