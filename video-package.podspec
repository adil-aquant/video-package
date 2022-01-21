require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "video-package"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/adil-aquant/video-package.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.dependency "React-Core"
  s.resource = 'ios/Resources/*.{storyboard,xcassets,png,jpg,jpeg}'
  s.swift_version = "5.0"
  s.static_framework = true
  s.resource_bundles = {
     'AquantVideoModule' => ['ios/Resources/*.{storyboard,xcassets,png,jpg,jpeg}']
   }

  s.dependency "React-Core"
  s.dependency 'OpenTok', '~> 2.21'
  s.dependency 'TensorFlowLiteSwift', '~> 2.6.0'
end
