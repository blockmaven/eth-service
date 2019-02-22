const express = require('express');
const TransactionController = require('../controllers/transaction.controller');

const initTransactionRoutes = () => {
  const TransactionRouter = express.Router();

  TransactionRouter.get('/:txhash/status', TransactionController.getTransactionStatus);

  return TransactionRouter;
};

module.exports = initTransactionRoutes;
