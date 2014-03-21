# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "bonnie_bundler"
  s.summary = "A Gem for creating and managing bonnie bundles"
  s.description = "A Gem for creating and managing bonnie bundles"
  s.email = "pophealth-talk@googlegroups.com"
  s.homepage = "http://github.com/projecttacoma/bonnie_bundler"
  s.authors = ["Andre Quina"]
  s.version = '1.0.0'

  # Fixme: this dependency should be added back once QME version 3 is released
  # s.add_dependency 'quality-measure-engine', '~>3'
  
  s.files = s.files = `git ls-files`.split("\n")
end


