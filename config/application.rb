# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
# require 'action_cable/engine'
# require 'sprockets/railtie'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# (Development/Test env only)
# Load .env* variables before the config (Settings) initializer is
# being run.
Dotenv::Railtie.load unless Rails.env.production?

module ComplianceBackend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq

    # Attach audit logging for requests
    require 'audit_log/audit_log'
    config.middleware.use Insights::API::Common::AuditLog::Middleware
    # Adjust params[tags] to be array
    require 'adjust_tags/middleware'
    config.middleware.use Insights::API::Common::AdjustTags::Middleware

    # FIXME: profile<->policy connections could fail on this
    config.active_record.has_many_inversing = false

    # GraphiQL
    if Rails.env.development?
      config.middleware.use Rack::MethodOverride
    end
  end
end
