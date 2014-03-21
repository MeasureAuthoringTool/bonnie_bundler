Mongoid.load!("config/mongoid.yml", :test) unless Mongoid.configured?
MONGO_DB = Mongoid.default_session
require 'quality-measure-engine'

module QME
  module DatabaseAccess
    # Monkey patch in the connection for the application
    def get_db
      Mongoid.default_session
    end
  end
end

