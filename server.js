const config = require('config');

const application = require('./lib');

application.start()
  .then(() => {
    application.logger.info(`API is Initialized`);
    application.logger.info(`App Name\t\t: ${config.app}`);
    application.logger.info(`Environment\t: ${process.env.NODE_ENV || 'development'}`);
    application.logger.info(`App Port\t\t: ${config.port}`);
  })
  .catch(error => {
    application.logger.error(`Failed to Load`);
    application.logger.error(error);
  });