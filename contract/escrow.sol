pragma solidity 0.5.0;


/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}


contract Governable {

    // list of admins, council at first spot
    address[] public admins;

    /**
    * event for admin addition
    * @param newAdmin address of the new admin
    * @param compositor address of the admin who added the new admin
    */
    event AdminAdded(address newAdmin, address compositor);

    /**
    * event for admin addition
    * @param admin address of the admin to be removed
    * @param eliminator address of the admin who is removing the above admin
    */
    event AdminRemoved(address admin, address eliminator);

    constructor() public {
        admins.length = 1;
        admins[0] = msg.sender;
    }

    modifier onlyAdmins() {
        (bool adminStatus, ) = isAdmin(msg.sender);
        require(adminStatus == true, "Not an admin");
        _;
    }

    function addAdmin(address _admin) public onlyAdmins {
        (bool adminStatus, ) = isAdmin(_admin);
        require(!adminStatus, "Already an admin");
        require(admins.length < 10, "Admins limit reached");
        admins[admins.length++] = _admin;
        emit AdminAdded(_admin, msg.sender);
    }

    function removeAdmin(address _admin) public onlyAdmins {
        (bool adminStatus, uint256 pos) = isAdmin(_admin);
        require(adminStatus, "Not an admin");
        // if not last element, switch with last
        if (pos < admins.length - 1) {
            admins[pos] = admins[admins.length - 1];
        }
        // then cut off the tail
        admins.length--;
        emit AdminRemoved(_admin, msg.sender);
    }

    function isAdmin(address _addr) public view returns (bool isAdmin, uint256 pos) {
        isAdmin = false;
        for (uint256 i = 0; i < admins.length; i++) {
            if (_addr == admins[i]) {
                isAdmin = true;
                pos = i;
            }
        }
    }

}


interface ERC20 {
    function balanceOf(address _owner) external view returns (uint256 balance);
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
}


contract Escrow is Governable {
    using SafeMath for uint256;

    enum JobState { Absent, Created, Assigned, Completed, Arbitration, Paid, Unacceptable }

    struct Job {
        bytes description;
        address vodiant;
        address vodeer;
        uint256 vodiantTokensStaked;
        uint256 payoutStartTime;
        uint256 arbitrationTime;
        address arbiter;
        bool vodiantDissatisfied;
        JobState status;
    }

    uint256 public nonce;
    address public token;
    uint256 public payoutPeriod;
    mapping ( uint256 => Job ) public jobDetails;

    event TokenSet(address _token);
    event PayoutPeriodSet(uint256 _payoutPeriod);
    event JobAdded(uint256 _nonce, address _vodiant, uint256 _tokensStaked);
    event JobAssigned(uint256 _nonce, address _vodiant, address _vodeer, uint256 _vodiantTokens);
    event WorkSubmitted(uint256 _nonce, address _vodeer);
    event VodiantDissatisfied(uint256 _nonce, address _vodiant);
    event DisputeRaised(uint256 _nonce, address _vodeer);
    event ArbiterAssigned(uint256 _nonce, address _arbiter);
    event VodeerPaid(uint256 _nonce, address _vodeer, uint256 _tokens);
    event PayoutClaimed(address beneficiary, uint256 tokens, bool isVodiant);
    event TokensRefunded(uint256 _nonce, address _vodiant, address _vodeer, uint256 _vodiantTokens);

    modifier checkStatus(uint256 _nonce, JobState state) {
        require(jobDetails[_nonce].status == state, "Job is at a different stage");
        _;
    }

    modifier isArbiter(uint256 _nonce) {
        require(jobDetails[_nonce].arbiter == msg.sender, "Not the arbiter for this job");
        _;
    }

    modifier isValidAddress(address _who) {
        require(_who != address(0), "Invalid address");
        _;
    }

    modifier isVodeer(uint256 _nonce) {
        require(jobDetails[_nonce].vodeer == msg.sender, "Not your job");
        _;
    }

    modifier isVodiant(uint256 _nonce) {
        require(jobDetails[_nonce].vodiant == msg.sender, "Not your job");
        _;
    }

    modifier hasTransferred(address beneficiary, uint256 tokens) {
        _;
        require(ERC20(token).transfer(beneficiary, tokens), "Insufficient funds in contract");
    }

    modifier isVodiantSatisfied(uint256 _nonce, bool _required) {
        string memory message;
        if (_required) {
            message = "Vodiant satisfied";
        } else {
            message = "Request already submitted";
        }

        require(jobDetails[_nonce].vodiantDissatisfied == _required, message);
        _;
    }

    constructor(address _token, uint256 _payoutPeriod) public {
        setToken(_token);
        setPayoutPeriod(_payoutPeriod);
    }

    function setToken(address _token) public onlyAdmins isValidAddress(_token) {
        token = _token;
        emit TokenSet(_token);
    }

    function setPayoutPeriod(uint256 _payoutPeriod) public onlyAdmins {
        require(_payoutPeriod > 0, "0 value entered");
        payoutPeriod = _payoutPeriod;
        emit PayoutPeriodSet(_payoutPeriod);
    }

    function addJob(bytes memory _description, uint256 _tokens) public {
        Job storage job = jobDetails[nonce];
        job.description = _description;
        job.vodiant = msg.sender;
        job.vodiantTokensStaked = _tokens;
        job.status = JobState.Created;

        emit JobAdded(nonce, msg.sender, _tokens);
        
        nonce = nonce.add(1);

        require(ERC20(token).transferFrom(msg.sender, address(this), _tokens), "Token transfer failed");
    }

    function applyForJob(
        uint256 _nonce
    ) 
        public 
        checkStatus(_nonce, JobState.Created) 
    {
        Job storage job = jobDetails[_nonce];
        
        job.vodeer = msg.sender;
        job.status = JobState.Assigned;

        emit JobAssigned(_nonce, job.vodiant, msg.sender, job.vodiantTokensStaked);
    }

    function submitWork(uint256 _nonce) 
        public
        isVodeer(_nonce)
        checkStatus(_nonce, JobState.Assigned) 
    {
        jobDetails[_nonce].status = JobState.Completed;
        jobDetails[_nonce].payoutStartTime = now;
        
        emit WorkSubmitted(_nonce, msg.sender);
    }

    function dissatisfactoryWorkSubmitted(uint256 _nonce) 
        public 
        checkStatus(_nonce, JobState.Completed) 
        isVodiant(_nonce)
        isVodiantSatisfied(_nonce, false)
    {
        require(now.sub(jobDetails[_nonce].payoutStartTime) <= payoutPeriod, "Payout period has passed");
        jobDetails[_nonce].vodiantDissatisfied = true;
        jobDetails[_nonce].status = JobState.Arbitration;
        jobDetails[_nonce].arbitrationTime = now;
        
        emit VodiantDissatisfied(_nonce, msg.sender);
    }

    function raiseDispute(uint256 _nonce, address _arbiter) 
        public 
        isVodeer(_nonce)
        isValidAddress(_arbiter) 
        checkStatus(_nonce, JobState.Arbitration) 
        isVodiantSatisfied(_nonce, true)
    {
        require(now.sub(jobDetails[_nonce].arbitrationTime) <= payoutPeriod, "Payout period has passed");   
        require(jobDetails[_nonce].arbiter == address(0), "Arbiter already assigned");
        jobDetails[_nonce].arbiter = _arbiter;

        emit DisputeRaised(_nonce, msg.sender);
        emit ArbiterAssigned(_nonce, _arbiter);
    }

    function claimPayout(
        uint256 _nonce
    ) 
        public
        hasTransferred(msg.sender, jobDetails[_nonce].vodiantTokensStaked)  
    {
        if (jobDetails[_nonce].status == JobState.Completed && 
            now.sub(jobDetails[_nonce].payoutStartTime) > payoutPeriod) {

            require(msg.sender == jobDetails[_nonce].vodeer, "Only vodeer can claim this payout");
            emit PayoutClaimed(msg.sender, jobDetails[_nonce].vodiantTokensStaked, false);
        } else if (jobDetails[_nonce].status == JobState.Arbitration &&
            now.sub(jobDetails[_nonce].arbitrationTime) > payoutPeriod) {
            
            require(msg.sender == jobDetails[_nonce].vodiant, "Only vodiant can claim this payout");
            emit PayoutClaimed(msg.sender, jobDetails[_nonce].vodiantTokensStaked, true);
        }

        jobDetails[_nonce].status = JobState.Paid;
    }

    function positiveVerdict(uint256 _nonce) 
        public 
        isArbiter(_nonce) 
        checkStatus(_nonce, JobState.Arbitration) 
        hasTransferred(jobDetails[_nonce].vodeer, jobDetails[_nonce].vodiantTokensStaked)
    {
        jobDetails[_nonce].status == JobState.Paid; 
        
        address vodeer = jobDetails[_nonce].vodeer;
        uint256 tokens = jobDetails[_nonce].vodiantTokensStaked;
       
        emit VodeerPaid(_nonce, vodeer, tokens);
    }

    function negativeVerdict(uint256 _nonce) 
        public 
        isArbiter(_nonce) 
        checkStatus(_nonce, JobState.Arbitration)
        hasTransferred(jobDetails[_nonce].vodiant, jobDetails[_nonce].vodiantTokensStaked) 
    {
        jobDetails[_nonce].status == JobState.Unacceptable;

        address vodiant = jobDetails[_nonce].vodiant;
        uint256 vodiantTokens = jobDetails[_nonce].vodiantTokensStaked;
        
        emit TokensRefunded(_nonce, vodiant, jobDetails[_nonce].vodeer, vodiantTokens);
    }
}
