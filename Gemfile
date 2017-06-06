source "http://rubygems.org"
gemspec

#gem 'health-data-standards', '3.4.4'

gem 'health-data-standards', :git => 'https://github.com/projectcypress/health-data-standards.git', :branch => 'multi_library_support'
gem 'quality-measure-engine', :git => 'https://github.com/pophealth/quality-measure-engine.git', :branch => 'master'
gem 'hqmf2js', :git => 'https://github.com/projecttacoma/hqmf2js.git', :branch => 'master'
gem 'hquery-patient-api', :git => 'https://github.com/projecttacoma/patientapi.git', :branch => 'QDM_5-0'
gem 'simplexml_parser', :git => 'https://github.com/projecttacoma/simplexml_parser.git', :branch => 'master'

# gem 'health-data-standards', :path => '../health-data-standards'
# gem 'quality-measure-engine', :path => '../quality-measure-engine'
# gem 'hqmf2js', :path => '../hqmf2js'
# gem 'hquery-patient-api', :path => '../patientapi'
# gem 'simplexml_parser', :path => '../simplexml_parser'

gem 'rails', '>= 4.0.0'
gem 'rake'
gem 'pry'
gem 'pry-nav'
gem 'tilt'
gem 'coffee-script'
gem 'sprockets'
gem "therubyracer", :require => 'v8'
gem 'mongoid'
gem 'rubyzip', '< 1.0.0'
gem 'diffy'

# needed for parsing value sets (we need to use roo rather than rubyxl because the value sets are in xls rather than xlsx)
gem 'roo'

group :test do
  gem 'simplecov', :require => false
  gem 'minitest', "~> 5.0"
  gem 'awesome_print', :require => 'ap'
  gem 'vcr'
  gem 'webmock'
end
