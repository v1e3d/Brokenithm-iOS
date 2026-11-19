# Gemfile.lock is deliberately NOT committed — see .gitignore.
#
# Resolving it needs the same Ruby as CI (3.3); macOS ships only 2.6, whose bundler picks
# Ruby-2.6-era gems that hard-fail on CI. So CI resolves fresh on Ruby 3.3 and the pin
# below is what keeps it reproducible: fastlane constrains its own dependencies tightly,
# and `~> 2.230` rules out a breaking 3.x.

source "https://rubygems.org"

gem "fastlane", "~> 2.230"
