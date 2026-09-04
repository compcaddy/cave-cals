require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'EasiestCalorieCounter.xcodeproj'))
app = project.new_target(:application, 'EasiestCalorieCounter', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'ECCTests', :ios, '17.0')
ui = project.new_target(:ui_test_bundle, 'ECCUITests', :ios, '17.0')
tests.add_dependency(app)
ui.add_dependency(app)
[['App', app], ['Tests', tests], ['UITests', ui]].each do |folder, target|
  group = project.main_group.new_group(folder, folder)
  Dir.glob(File.join(root, folder, '**', '*.swift')).sort.each do |path|
    ref = group.new_file(path.delete_prefix(File.join(root, folder) + '/'))
    target.source_build_phase.add_file_reference(ref)
  end
end
app.resources_build_phase.add_file_reference(project.main_group.new_file('App/Assets.xcassets'))
app.resources_build_phase.add_file_reference(project.main_group.new_file('App/PrivacyInfo.xcprivacy'))
fonts = project.main_group.new_file('App/Fonts')
fonts.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(fonts)
project.targets.each do |target|
  target.build_configurations.each do |config|
    s = config.build_settings
    s['SWIFT_VERSION'] = '5.0'
    s['TARGETED_DEVICE_FAMILY'] = '1'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "com.phil.EasiestCalorieCounter2#{target == app ? '' : '.' + target.name}"
    s['MARKETING_VERSION'] = '1.0'
    s['CURRENT_PROJECT_VERSION'] = '1'
    s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    s['SUPPORTS_MACCATALYST'] = 'NO'
    s['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    s['SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    s['CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]'] = 'NO'
  end
end
app.build_configurations.each do |config|
  s = config.build_settings
  s['INFOPLIST_FILE'] = 'App/Info.plist'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'Easiest Calories'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  s['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait'
  s['CODE_SIGN_ENTITLEMENTS'] = 'App/EasiestCalorieCounter.entitlements'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
end
tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/EasiestCalorieCounter.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/EasiestCalorieCounter'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = 'EasiestCalorieCounter' }
app.add_system_framework('CloudKit')
app.add_system_framework('AVFoundation')
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui)
scheme.save_as(project.path, 'EasiestCalorieCounter', true)
project.save
