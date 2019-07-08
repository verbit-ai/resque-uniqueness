
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'resque_scheduler_unique_jobs/version'

Gem::Specification.new do |spec|
  spec.name          = 'resque-scheduler-unique-jobs'
  spec.version       = ResqueSchedulerUniqueJobs::VERSION
  spec.authors       = ['Olexandr Hoshylyk']
  spec.email         = ['gashuk95@gmail.com']

  spec.summary       = 'Gem for resque unique jobs'
  spec.description   = 'Implement unique jobs system like sidekiq-unique-jobs gem'
  spec.homepage      = 'https://github.com/Warrior109/resque-scheduler-unique-jobs'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://github.com/Warrior109/resque-scheduler-unique-jobs'

    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://github.com/Warrior109/resque-scheduler-unique-jobs'
    spec.metadata['changelog_uri'] = 'https://github.com/Warrior109/resque-scheduler-unique-jobs'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'resque', '~> 2.0.0'
  spec.add_dependency 'resque-scheduler', '~> 4.0'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end