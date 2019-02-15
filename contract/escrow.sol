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
        uint256 vodeerTokensStaked;
        uint256 vodiantTokensStaked;
        address arbiter;
        bool vodiantDissatisfied;
        JobState status;
    }

    uint256 nonce;
    address token;
    mapping ( uint256 => Job ) public jobDetails;

    event TokenSet(address _token);
    event JobAdded(uint256 _nonce, address _vodiant, uint256 _tokensStaked);
    event JobAssigned(uint256 _nonce, address _vodiant, uint256 _vodiantTokens, address _vodeer, uint256 _vodeerTokens);
    event WorkSubmitted(uint256 _nonce, address _vodeer);
    event VodiantDissatisfied(uint256 _nonce, address _vodiant);
    event DisputeRaised(uint256 _nonce, address _vodeer);
    event ArbiterAssigned(uint256 _nonce, address _arbiter);
    event VodeerPaid(uint256 _nonce, address _vodeer, uint256 _tokens);
    event TokensRefunded(uint256 _nonce, address _vodiant, uint256 _vodiantTokens, address _vodeer, uint256 _vodeerTokens);

    constructor(address _token) public {
        setToken(_token);
    }

    function setToken(address _token) public {
        require(_token != address(0), "Invalid address");
        token = _token;
        emit TokenSet(_token);
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

    function applyForJob(uint256 _nonce, uint256 _tokens) public {
        Job storage job = jobDetails[_nonce];
        require(job.status == JobState.Created, "Job not available");
        
        job.vodeer = msg.sender;
        job.vodeerTokensStaked = _tokens;
        job.status = JobState.Assigned;

        require(ERC20(token).transferFrom(msg.sender, address(this), _tokens), "Token transfer failed");
        emit JobAssigned(_nonce, job.vodiant, job.vodiantTokensStaked, msg.sender, _tokens);
    }

    function submitWork(uint256 _nonce) public {
        require(jobDetails[_nonce].vodeer == msg.sender, "Not your job");
        require(jobDetails[_nonce].status == JobState.Assigned, "Job already submitted");

        jobDetails[_nonce].status = JobState.Completed;
        emit WorkSubmitted(_nonce, msg.sender);
    }

    function dissatisfactoryWorkSubmitted(uint256 _nonce) public {
        require(jobDetails[_nonce].vodiant == msg.sender, "Not your job");
        require(jobDetails[_nonce].status == JobState.Completed, "Job is at a different stage");
        require(!jobDetails[_nonce].vodiantDissatisfied, "Request already submitted");

        jobDetails[_nonce].vodiantDissatisfied = true;
        emit VodiantDissatisfied(_nonce, msg.sender);
    }

    function raiseDispute(uint256 _nonce) public {
        require(jobDetails[_nonce].vodeer == msg.sender, "Not your job");
        require(jobDetails[_nonce].status == JobState.Completed, "Job is at a different stage");
        require(jobDetails[_nonce].vodiantDissatisfied, "Vodiant satisfied");

        jobDetails[_nonce].status = JobState.Arbitration;
        emit DisputeRaised(_nonce, msg.sender);
    }

    function assignArbiter(uint256 _nonce, address _arbiter) public onlyAdmins {
        require(jobDetails[_nonce].status == JobState.Arbitration, "Job is at a different stage");
        require(jobDetails[_nonce].arbiter == address(0), "Arbiter already assigned");
        require(_arbiter != address(0), "Invalid address");

        jobDetails[_nonce].arbiter = _arbiter;
        emit ArbiterAssigned(_nonce, _arbiter);
    }

    function positiveVerdict(uint256 _nonce) public {
        require(jobDetails[_nonce].status == JobState.Arbitration, "Job is at a different stage");
        require(jobDetails[_nonce].arbiter == msg.sender, "Not the arbiter for this job");

        jobDetails[_nonce].status == JobState.Paid; 
        
        address vodeer = jobDetails[_nonce].vodeer;
        uint256 tokens = jobDetails[_nonce].vodeerTokensStaked.add(jobDetails[_nonce].vodiantTokensStaked);
        
        require(ERC20(token).transfer(vodeer, tokens), "Insufficient funds in contract");
        emit VodeerPaid(_nonce, vodeer, tokens);
    }

    function negativeVerdict(uint256 _nonce) public {
        require(jobDetails[_nonce].status == JobState.Arbitration, "Job is at a different stage");
        require(jobDetails[_nonce].arbiter == msg.sender, "Not the arbiter for this job");

        jobDetails[_nonce].status == JobState.Unacceptable;

        address vodeer = jobDetails[_nonce].vodeer;
        uint256 vodeerTokens = jobDetails[_nonce].vodeerTokensStaked;
        address vodiant = jobDetails[_nonce].vodiant;
        uint256 vodiantTokens = jobDetails[_nonce].vodiantTokensStaked;

        require(ERC20(token).transfer(vodeer, vodeerTokens), "Insufficient funds in contract");
        require(ERC20(token).transfer(vodiant, vodiantTokens), "Insufficient funds in contract");
        emit TokensRefunded(_nonce, vodiant, vodiantTokens, vodeer, vodeerTokens);
    }
}
