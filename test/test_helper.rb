ENV["RAILS_ENV"] = "test"
require_relative "./simplecov_init"
require 'minitest/autorun'
require 'rails'
require 'rails/test_help'
require 'hquery-patient-api'
require 'diffy'
APP_CONFIG = {'vsac'=> {'auth_url'=> 'https://vsac.nlm.nih.gov/vsac/ws',
      'content_url' => 'https://vsac.nlm.nih.gov/vsac/svs',
      'utility_url' => 'https://vsac.nlm.nih.gov/vsac',
      'default_profile' => 'MU2 Update 2016-04-01'}}

PROJECT_ROOT = File.expand_path("../../", __FILE__)
require File.join(PROJECT_ROOT, 'lib', 'bonnie_bundler')
BonnieBundler.logger = Log4r::Logger.new("Bonnie Bundler")
BonnieBundler.logger.outputters = Log4r::Outputter.stdout

def dump_db
  Mongoid.default_client.collections.each do |c|
    c.drop()
  end
  FileUtils.rm_r 'db' if File.exists? 'db'
end

def get_ticket_granting_ticket
  api = Util::VSAC::VSACAPI.new(config: APP_CONFIG['vsac'], username: ENV['VSAC_USERNAME'], password: ENV['VSAC_PASSWORD'])
  return api.ticket_granting_ticket
end

Mongoid.logger.level = Logger::INFO
Mongo::Logger.logger.level = Logger::INFO
dump_db

# Supplied from bonnie, needed for expected_values testing
class Record
  field :type, type: String
  field :measure_ids, type: Array
  field :source_data_criteria, type: Array
  field :expected_values, type: Array

  belongs_to :user
  scope :by_user, ->(user) { where({'user_id'=>user.id}) }
end


class User
  include Mongoid::Document
  include Mongoid::Timestamps
end
