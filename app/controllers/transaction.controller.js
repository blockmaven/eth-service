const Ethereum = require('../../lib/ethereum');
const Responder = require('../../lib/expressResponder');

const status = {
  NOT_REACHED: {
    status: "NOT_REACHED",
    message: "Transaction does not reached to blockchain nodes!"
  },
  PENDING: {
    status: "PENDING",
    message: "Trasaction is in Pending State"
  },
  REVERTED: {
    status: "FAILED",
    message: "Transaction Failed",
    possibleReason: "REVERTED"
  },
  OUTOFGAS: {
    status: "FAILED",
    message: "Transaction Failed",
    possibleReason: "Out of Gas"
  },
  SUCCESS: {
    status: "SUCCESS",
    message: "Transaction Completed Successfully!"
  }
};

class Transaction {
  static async getTransactionStatus(req, res) {
    try {
      const reciept = await Ethereum.getTransactionReceipt(req.params.txhash);
      if(!reciept) {
        const transaction = await Ethereum.getTransaction(req.params.txhash);
        if(!transaction) {
          return Responder.success(res, status.NOT_REACHED);
        }
        return Responder.success(res, status.PENDING);
      }
      if(reciept.status == '0x0') {
        const transaction = await Ethereum.getTransaction(req.params.txhash);
        if(reciept.gasUsed == transaction.gas) {
          return Responder.success(res, status.OUTOFGAS);
        }
        return Responder.success(res, status.REVERTED);
      }
      return Responder.success(res, status.SUCCESS);
    } catch (err) {
      return Responder.operationFailed(res, err);
    }
  }
}

module.exports = Transaction;
