source "http://rubygems.org"
gemspec
gem 'health-data-standards', :git => 'https://github.com/projectcypress/health-data-standards.git', :branch => 'master'
#gem 'health-data-standards', :path => '../health-data-standards'

gem 'hqmf2js', :git => 'https://github.com/pophealth/hqmf2js.git', :branch => 'develop'

gem 'hquery-patient-api', :git => 'https://github.com/pophealth/patientapi.git', :branch => 'develop'

#gem 'hqmf2js', :path => '../hqmf2js'
gem 'quality-measure-engine', :git => 'https://github.com/pophealth/quality-measure-engine.git', :branch => 'mongoid_refactor'
#gem 'quality-measure-engine', :path => '../quality-measure-engine'

gem 'rails', '3.2.14'
gem 'rake'
gem 'pry'
gem 'tilt'
gem 'coffee-script'
gem 'sprockets'
gem "therubyracer", :require => 'v8'
gem 'mongoid'

# needed for parsing value sets (we need to use roo rather than rubyxl because the value sets are in xls rather than xlsx)
gem 'roo'

group :test do
  gem 'simplecov', :require => false

  gem 'minitest', "~> 4.0"
  gem 'turn', :require => false
  gem 'awesome_print', :require => 'ap'
end

