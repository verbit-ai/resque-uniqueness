# Resque::Plugins::Uniqueness

<!-- MarkdownTOC -->

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Installation](#installation)
- [Global Configuration](#global-configuration)
  - [enabled](#enabled)
- [Locks](#locks)
  - [Until Executing](#until-executing)
  - [Until And While Executing](#until-and-while-executing)
  - [While Executing](#while-executing)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

<!-- /MarkdownTOC -->

## Introduction

The goal of this gem is to ensure your Resque jobs are unique. We do this by creating unique keys in Redis based on how you configure uniqueness. This gem it's a resque implementation with resque-scheduler support of https://github.com/mhenrixon/sidekiq-unique-jobs/

## Requirements

- Resque `~> 2.0.0`
- Ruby `>= 2.3`

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'resque-uniqueness'
```

And then execute:

```bash
bundle
```

Or install it yourself as:

```bash
gem install resque-uniqueness
```

## Global Configuration

You can set a default lock type for all workers with:
```ruby 
Resque::Uniqueness.default_lock_type = :while_executing
```
By default all jobs have an `until_executing` lock type.

### enable plugin

```ruby
class TestWorker
  include Resque::Plugins::Uniqueness
  
  def self.perform(*args)
  end
end
```

All workers and their descendants, which include this plugin, will already have an locking system.
To disable locking for some particular child, write:

``` ruby
class ChildWithDisabledLocking < Parent
  @lock_type = :none
end
```

## Locks

### Until Executing

```ruby
@lock_type = :until_executing
```

Locks from when the client pushes the job to the queue. Will be unlocked before the server starts processing the job.

### Until And While Executing

```ruby
@lock_type = :until_and_while_executing
```

Locks when the client pushes the job to the queue. The queue will be unlocked when the server starts processing the job. The server then goes on to creating a runtime lock for the job to prevent simultaneous jobs from being executed. As soon as the server starts processing a job, the client can push the same job to the queue.

### While Executing

```ruby
@lock_type = :while_executing
```

With this lock type it is possible to put any number of these jobs on the queue, but as the server pops the job from the queue it will create a lock and then wait until other locks are done processing. It _looks_ like multiple jobs are running at the same time but in fact the second job will only be waiting for the first job to finish.

## Filtering arguments

```ruby
def self.unique_args(first, second, _third)
  [first, second]
end
```

Overriding this method you could to choose which arguments will be used for unique lock. You could t
provide empty array, to make lock only by class.
Method always should returns array.

## Testing

You should to run resque workers:

`QUEUE=* COUNT=5 bundle exec rake resque:workers`

and also resque scheduler:

`bundle exec resque:scheduler`

And after it:

`bundle exec rake spec`

## Contributing

1. Fork it
1. Create your feature branch (`git checkout -b my-new-feature`)
1. Commit your changes (`git commit -am 'Add some feature'`)
1. Push to the branch (`git push origin my-new-feature`)
1. Create new Pull Request

Bug reports and pull requests are welcome on GitHub at https://github.com/verbit/resque-uniqueness. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
