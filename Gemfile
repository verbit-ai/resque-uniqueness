# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development do
  gem 'pry'
  gem 'rubocop'
  gem 'rubocop-rspec'
end

group :development, :test do
  gem 'resque-retry'
end

group :test do
  gem 'ougai' # JSON logs
  gem 'rspec', '~> 3.0'
  gem 'rspec-its' # its(:foo) syntax
  gem 'saharspec', '~> 0.0.5' # some syntactic sugar for RSpec
  gem 'timecop'
end
