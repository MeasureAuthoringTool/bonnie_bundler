module BonnieBundler
  class Railtie < Rails::Railtie
    initializer 'Rails logger' do
      BonnieBundler.logger = Rails.logger
    end
    rake_tasks do
      Dir[File.join(File.dirname(__FILE__),'tasks/*.rake')].each { |f| load f }
    end

  end
end