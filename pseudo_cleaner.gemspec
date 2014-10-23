# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pseudo_cleaner/version'

Gem::Specification.new do |spec|
  spec.name          = "pseudo_cleaner"
  spec.version       = PseudoCleaner::VERSION
  spec.authors       = ["RealNobody"]
  spec.email         = ["RealNobody1@cox.net"]
  spec.description   = %q{A compromise db cleaning strategy between truncate and transactions.}
  spec.summary       = %q{A compromise db cleaning strategy between truncate and transactions.}
  spec.homepage      = "https://github.com/RealNobody/pseudo_cleaner"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "colorize"
  spec.add_runtime_dependency "database_cleaner"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end