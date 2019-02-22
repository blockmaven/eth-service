const initTransactionRoutes = require('./transaction.route');

function initRoutes(app) {
  app.use('/transactions', initTransactionRoutes());
}

module.exports = initRoutes;
