# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'websocks/version'

Gem::Specification.new do |spec|
  spec.name          = "websocks"
  spec.version       = Websocks::VERSION
  spec.authors       = ["dramforever"]
  spec.email         = ["dramforever@live.com"]

  spec.summary       = %q{Websocks the proxy}
  spec.description   = %q{A simple socket proxy over websockets with a SOCKS 5 front end}
  spec.homepage      = "https://github.com/dramforever/websocks"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_runtime_dependency "eventmachine", "~> 1.2.0.1"
  spec.add_runtime_dependency "bindata", "~> 2.3.1"
end
