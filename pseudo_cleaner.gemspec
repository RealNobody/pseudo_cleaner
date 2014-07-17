# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pseudo_cleaner/version'

Gem::Specification.new do |spec|
  spec.name          = "pseudo_cleaner"
  spec.version       = PseudoCleaner::VERSION
  spec.authors       = ["RealNobody"]
  spec.email         = ["RealNobody1@cox.net"]
  spec.description   = %q{A db cleaner}
  spec.summary       = %q{a db cleaner}
  spec.homepage      = "https://github.com/RealNobody/pseudo_cleaner"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
