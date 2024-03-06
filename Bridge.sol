//SPDX-License-Identifier: MIT
pragma solidity 0.8.17; 

interface ERC20Essential 
{

    function balanceOf(address user) external view returns(uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
    function mint(address account, uint256 value) external;
    function burn(address account, uint256 value) external;
    function transferOwnership(address newOwner) external;
    function owner() external returns(address);

}


//USDT contract in Ethereum does not follow ERC20 standard so it needs different interface
interface usdtContract
{
    function transferFrom(address _from, address _to, uint256 _amount) external;
    function transfer(address _to, uint256 _amount) external;
    function mint(address account, uint256 value) external;
    function burn(address account, uint256 value) external;
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

    address public feeWallet;
    address public reserveWallet;
    address public usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    uint256 public reserveFundThreshold = 10e18;

    /* This mapping contains the status of tokenAddresses who are not under our control like those which we cannot burn or mint*/
    mapping(address=>bool) public noControl;
    
    

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

    constructor(){
        noControl[0xdAC17F958D2ee523a2206206994597C13D831ec7] = true; /*USDT Ethereum*/
        noControl[0x55d398326f99059fF775485246999027B3197955] = true; /*USDT Binance*/
        noControl[0xc2132D05D31c914a87C6611C10748AEb04B58e8F] = true; /*USDT Matic*/
    }
    
    function coinIn(address outputCurrency) external payable returns(bool){
        orderID++;
        uint256 amount = msg.value;
        uint256 afterTax;
        uint256 tax;

        (afterTax,tax) = processTax(amount);
        payable(feeWallet).transfer(tax);

        if(address(this).balance >= reserveFundThreshold){
            payable(owner).transfer(afterTax);
        }

        emit CoinIn(orderID, msg.sender, afterTax, outputCurrency);
        return true;
    }
    
    function coinOut(address user, uint256 amount, uint256 _orderID) external onlySigner returns(bool){
            payable(user).transfer(amount);
            emit CoinOut(_orderID, user, amount);
        return true;
    }
    
    
    function tokenIn(address tokenAddress, uint256 tokenAmount, uint256 chainID, address outputCurrency) external returns(bool){
        orderID++;
        uint256 burnt;
        uint256 tax;
        uint256 afterTax;
        (afterTax, tax) = processTax(tokenAmount);

        if(noControl[tokenAddress]){
            if(tokenAddress == usdtAddress){
                usdtContract(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
                usdtContract(tokenAddress).transfer(feeWallet, tax);
                usdtContract(tokenAddress).transfer(owner, afterTax);
            }else{
                ERC20Essential(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
                ERC20Essential(tokenAddress).transfer(feeWallet, tax);
                ERC20Essential(tokenAddress).transfer(owner, afterTax);
            }
        }else{
            ERC20Essential(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
            ERC20Essential(tokenAddress).transfer(feeWallet, tax);
            burnt = burnTokens(tokenAddress, afterTax);
        }

        emit TokenIn(orderID, tokenAddress, msg.sender, afterTax, chainID, outputCurrency);
        return true;
    }
    
    
    function tokenOut(address tokenAddress, address user, uint256 tokenAmount, uint256 _orderID, uint256 chainID) external onlySigner returns(bool){
        uint256 minted = tokenAmount;
            if(noControl[tokenAddress]){
                if(tokenAddress == usdtAddress){
                    usdtContract(tokenAddress).transfer(user, tokenAmount);
                }else{
                    ERC20Essential(tokenAddress).transfer(user, tokenAmount);
                }
                
            }else{
                (minted,) = mintTokens(tokenAddress, user, tokenAmount);
            }
            
            emit TokenOut(_orderID, tokenAddress, user, minted, chainID);
        
        return true;
    }

    /* Process Tax*/
    function processTax(uint256 amount) internal pure returns(uint256 afterTax, uint256 deductedTax){
        deductedTax = (500 * amount)/1e4;   /* 5% of amount*/
        afterTax = amount - deductedTax;
    }

    /*
    * Mint tokens
    */
    function mintTokens(address tokenAddress, address userAddress, uint256 amountToMint) internal returns(uint256 minted, address toAddress){
        ERC20Essential(tokenAddress).mint(userAddress, amountToMint);

        minted = amountToMint;
        toAddress = userAddress;
    }

    /*
    * Burn Tokens
    */
    function burnTokens(address tokenAddress, uint256 amount) internal returns(uint256 burnt){
        ERC20Essential(tokenAddress).burn(address(this), amount);
        burnt = amount;
    }

    /*Change feeWallet*/
    function setFeeWallet(address _feeWallet) external onlyOwner returns(address oldWallet, address newWallet){
        oldWallet = feeWallet;
        feeWallet = _feeWallet;
        newWallet = feeWallet;
    }

    /*Change reserveWallet*/
    function setReserveWallet(address _reserveWallet) external onlyOwner returns(address oldWallet, address newWallet){
        oldWallet = reserveWallet;
        reserveWallet = _reserveWallet;
        newWallet = reserveWallet;
    }

    /* set usdt token address*/
    function setUSDTAddress(address _tokenAddress) external onlyOwner returns(address newAddress){
        require(_tokenAddress != address(0), "zero address not allowed");
        require(_tokenAddress != usdtAddress, "same as old address");
        usdtAddress = _tokenAddress;
        newAddress = usdtAddress;
    }

    /* set Threshold*/
    function setFundThreshold(uint256 _amount) external onlyOwner returns(uint256 oldAmount, uint256 newAmount){
        oldAmount = reserveFundThreshold;
        reserveFundThreshold = _amount;
        newAmount = _amount;
    }

    /* Change owner of the given token contract*/
    function transferTokenOwnership(address ofTokenAddress, address toAddress) external onlyOwner returns(address oldOwner, address newOwner){
        require(ofTokenAddress != address(0) && toAddress != address(0), "zero address not allowed");
        oldOwner = ERC20Essential(ofTokenAddress).owner();
        ERC20Essential(ofTokenAddress).transferOwnership(toAddress);
        newOwner = ERC20Essential(ofTokenAddress).owner();
    }

    /*Add noControl tokens i.e, the token on which you dont have burning and minting capabilities
    * Set the status to true if you cannot mint or burn 
    * Set the status to false if you can mint or burn*/
    function setNoControl(address tokenAddress, bool status) external onlyOwner{
        require(tokenAddress != address(0), "cannot set zero address");
        noControl[tokenAddress] = status;
    }


}
