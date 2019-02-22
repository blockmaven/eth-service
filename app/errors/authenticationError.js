const BaseError = require('./base');

class AuthenticationError extends BaseError {

  constructor(message) {
    super(message, 401);
  }

}

module.exports =  AuthenticationError;
