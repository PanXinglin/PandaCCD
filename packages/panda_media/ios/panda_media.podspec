Pod::Spec.new do |s|
  s.name = 'panda_media'
  s.version = '0.1.0'
  s.summary = 'System media codecs and Vision face landmarks for PandaCCD'
  s.description = s.summary
  s.homepage = 'https://example.invalid/panda-ccd'
  s.license = { :type => 'BSD-3-Clause' }
  s.author = { 'PandaCCD' => 'local@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'panda_media/Sources/panda_media/**/*.swift'
  s.resource_bundles = { 'panda_media_privacy' => ['panda_media/Sources/panda_media/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.frameworks = 'Vision', 'AVFoundation', 'ImageIO', 'CoreMedia', 'CoreVideo', 'Photos'
end
