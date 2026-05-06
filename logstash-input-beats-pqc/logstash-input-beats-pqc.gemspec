BEATS_PQC_VERSION = File.read(File.expand_path(File.join(File.dirname(__FILE__), "VERSION"))).strip unless defined?(BEATS_PQC_VERSION)

Gem::Specification.new do |s|
  s.name            = "logstash-input-beats-pqc"
  s.version         = BEATS_PQC_VERSION
  s.licenses        = ["Apache License (2.0)"]
  s.summary         = "Receives Beats events over PQC TLS"
  s.description     = "Experimental Logstash input plugin for Beats/Lumberjack over TLS 1.3 with X25519MLKEM768."
  s.authors         = ["PQC ELK Lab"]
  s.email           = "pqc-lab@example.local"
  s.homepage        = "https://example.local/pqc-elk"
  s.require_paths   = ["lib"]

  s.files = Dir["lib/**/*", "src/**/*", "*.gemspec", "*.md", "Gemfile", "Rakefile", "VERSION", "docs/**/*"]
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency "logstash-codec-plain"
  s.add_development_dependency "bundler"
  s.add_development_dependency "rspec"

  s.platform = 'java'
end
