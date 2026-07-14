payments_api_url = ENV.fetch('PAYMENTS_API_URL')
stripe_secret_key = ENV.fetch('STRIPE_SECRET_KEY')

abort 'STRIPE_SECRET_KEY was empty' if stripe_secret_key.empty?

puts "Keyway Rails demo booted on Rails #{Rails.version}."
puts "  PAYMENTS_API_URL: #{payments_api_url}"
puts '  STRIPE_SECRET_KEY: available (value not printed)'
