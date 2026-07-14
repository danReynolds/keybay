require_relative 'boot'

require 'rails'
require 'active_support/railtie'

Bundler.require(*Rails.groups)

module KeywayDemo
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
  end
end
