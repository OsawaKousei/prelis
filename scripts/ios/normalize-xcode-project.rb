#!/usr/bin/env ruby
require 'fileutils'
require 'tmpdir'
require 'xcodeproj'

unless [[], ['--write'], ['--stdin']].include?(ARGV)
  abort 'Usage: normalize-xcode-project.rb [--write|--stdin]'
end
project_file = File.expand_path('../../apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj', __dir__)
original = ARGV == ['--stdin'] ? STDIN.read : File.binread(project_file)
normalized = Dir.mktmpdir('prelis-xcode-format-') do |directory|
  project = File.join(directory, 'PrelisMobile.xcodeproj')
  FileUtils.mkdir_p(project)
  file = File.join(project, 'project.pbxproj')
  File.binwrite(file, original)
  before = Xcodeproj::Plist.read_from_path(file)
  Xcodeproj::Project.open(project).save
  abort 'Normalization changed project settings; review required.' unless before == Xcodeproj::Plist.read_from_path(file)
  File.binread(file)
end

if ARGV == ['--stdin']
  STDOUT.write(normalized)
elsif original == normalized
  puts 'Xcode project format: OK'
elsif ARGV == ['--write']
  File.binwrite(project_file, normalized)
  puts 'Xcode project normalized (settings unchanged).'
else
  abort 'Xcode project format differs. Run scripts/ios/normalize-xcode-project.sh on Ubuntu and review the diff.'
end
