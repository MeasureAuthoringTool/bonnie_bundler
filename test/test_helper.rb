require_relative "./simplecov"
require 'test/unit'
require 'turn'
require 'rails'
require 'hquery-patient-api'
APP_CONFIG = {'nlm'=>{'ticket_url'=>'foo', 'api_url'=>'bar'}}

PROJECT_ROOT = File.expand_path("../../", __FILE__)
require File.join(PROJECT_ROOT, 'lib', 'bonnie_bundler')
BonnieBundler.logger = Log4r::Logger.new("Bonnie Bundler")
BonnieBundler.logger.outputters = Log4r::Outputter.stdout

def dump_db
  Mongoid.default_session.drop()
  FileUtils.rm_r 'db' if File.exists? 'db'
end
dump_db

# Supplied from bonnie, needed for expected_values testing
class Record
  field :type, type: String
  field :measure_ids, type: Array
  field :source_data_criteria, type: Array
  field :expected_values, type: Hash

  belongs_to :user
  scope :by_user, ->(user) { where({'user_id'=>user.id}) }
end


class User
  include Mongoid::Document
  include Mongoid::Timestamps
end