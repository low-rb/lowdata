# frozen_string_literal: true

require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name = 'lowdata'
  spec.version = LowData::VERSION
  spec.authors = ['maedi']
  spec.email = ['maediprichard@gmail.com']

  spec.summary = 'The repository pattern with a twist; Data Expressions'
  spec.description = 'The repository pattern with data expressions + the usual query building'
  spec.homepage = 'https://github.com/low-rb/lowdata'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/low-rb/lowdata/src/branch/main'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir.glob('{lib,config}/**/*')
  end

  spec.require_paths = ['lib']
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_dependency 'expressions', '~> 0.4'
  spec.add_dependency 'lowtype', '~> 1.6'
  spec.add_dependency 'sequel', '~> 5.0'
end
