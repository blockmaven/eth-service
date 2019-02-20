const fs = require('fs');
const _ = require('lodash');
const path = require('path');
const Web3 = require('web3');
const solc = require('solc');
const config = require('config');
const Transaction = require('ethereumjs-tx');

const logger = require('./logger');

class Ethereum {
  constructor() {
    this.web3 = new Web3(new Web3.providers.HttpProvider(config.eth_address));
    this.contracts = {};
    this.contracts_folder = null;
    if(config.contracts_path) {
      const contracts_folder_path = path.join(__dirname, '..', config.contracts_path);
      if(fs.existsSync(contracts_folder_path)) {
        this.contracts_folder = contracts_folder_path;
        this.loadContracts();
      }
    }
  }

  loadContracts() {
    const files = fs.readdirSync(this.contracts_folder);
    const solfiles = _.filter(files, file => _.endsWith(file, '.sol'));
    _.forEach(solfiles, file => {
      this.loadContract(file);
    });
  }

  loadContract(file) {
    const rawCodeFs = fs.readFileSync(path.join(this.contracts_folder, file));
    const rawcode = rawCodeFs.toString();
    const contractname = _.upperFirst(file).split('.sol')[0];
    const contractdetails = solc.compile(rawcode)
      .contracts[`:${contractname}`];
    const abi = JSON.parse(contractdetails.interface);
    const contract = this.web3.eth.contract(abi);
    this.contracts[contractname.toLowerCase()] = {
      bytecode: contractdetails.bytecode,
      contract,
    };
  }

  async deployContract(type, from, privatekey, gasLimit, ...args) {
    const contracttodeploy = this._createDeployableContract(type, args);
    const txHash = await this.makeTransaction(
      contracttodeploy,
      from,
      privatekey,
      gasLimit,
    );
    return await this.waitForTransactionReceipt(txHash);
  }

  async callContractFunction(type, contractaddress, funcname, useGetdata = false, ...args) {
    try {
      const contract = this.contracts[type.toLowerCase()]
        .contract.at(contractaddress);

      if (!useGetdata) {
        return await contract[funcname](...args);
      }

      return await contract[funcname].getData(...args);
    } catch (error) {
      throw error;
    }
  }

  async makeTransaction(data, from, privatekey, to, attempt = 0) {
    try {
      const gasLimit = config.gasLimit || this.web3.eth.estimateGas({data, from, to});
      const [nonce, gasprice] = await Promise.all([
        this.web3.eth.getTransactionCount(from),
        this.web3.eth.gasPrice,
      ]);
      const transaction = {
        nonce: this.web3.toHex(nonce + attempt),
        gasPrice: this.web3.toHex(gasprice),
        gasLimit: this.web3.toHex(gasLimit),
        to,
        data,
      };
      const rawTransaction = new Transaction(transaction);
      const bufferedPrivatekey = new Buffer(privatekey, 'hex');
      rawTransaction.sign(bufferedPrivatekey);
      const serializedTransaction = rawTransaction.serialize().toString('hex');
      const txhash = await this.web3.eth.sendRawTransaction(
        '0x' + serializedTransaction
      );
      return txhash;
    } catch (error) {
      logger.error(error);
      if (attempt < 3 && error.message === 'nonce too low') {
        return await this.makeTransaction(
          data,
          from,
          privatekey,
          gasLimit,
          to,
          attempt + 1
        );
      }
      throw error;
    }
  }

  async getTransactionReceipt(txhash) {
    return await this.web3.eth.getTransactionReceipt(txhash);
  }

  async waitForTransactionReceipt(txhash, time = 0) {
    logger.info(`Tracking Transaction : ${txhash}, since ${time/1000} seconds`);
    const receipt = await this.getTransactionReceipt(txhash);
    if (time > 3600000) {
      throw new Error("It's 1 hour and not mined since");
    }
    if (time > 60000 && time <= 70000) {
      const transactionData = await this.web3.eth.getTransaction(txhash);
      if (!transactionData) {
        throw new Error('Not reached to blockchain nodes');
      }
    }
    if (receipt === null) {
      await this._timeout(5000);
      return await this.waitForTransactionReceipt(txhash, time + 5000);
    } else {
      logger.info(`Transaction Completed : ${txhash}`);
      return receipt;
    }
  }

  toAscii(hex) {
    return this.web3.toAscii(hex);
  }

  async _timeout(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  _createDeployableContract(type, ...args) {
    if (!this.contracts[type]) {
      throw new Error('No Such Contract Found');
    }

    return this.contracts[type].contract.new.getData(...args, {
      data: '0x' + this.contracts[type].bytecode,
    });
  }
}

module.exports = new Ethereum();
