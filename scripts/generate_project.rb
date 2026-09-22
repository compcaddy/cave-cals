require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'CaveCals.xcodeproj'))
app = project.new_target(:application, 'CaveCals', :ios, '17.0')
tests = project.new_target(:unit_test_bundle, 'ECCTests', :ios, '17.0')
ui = project.new_target(:ui_test_bundle, 'ECCUITests', :ios, '17.0')
widget = project.new_target(:app_extension, 'QuickLogWidget', :ios, '17.0')
app.add_dependency(widget)
tests.add_dependency(app)
ui.add_dependency(app)
[['App', app], ['Tests', tests], ['UITests', ui], ['Widgets', widget]].each do |folder, target|
  group = project.main_group.new_group(folder, folder)
  Dir.glob(File.join(root, folder, '**', '*.swift')).sort.each do |path|
    ref = group.new_file(path.delete_prefix(File.join(root, folder) + '/'))
    target.source_build_phase.add_file_reference(ref)
  end
end
shared = project.main_group.new_group('Shared', 'Shared')
Dir.glob(File.join(root, 'Shared', '*.swift')).sort.each do |path|
  ref = shared.new_file(File.basename(path))
  [app, widget].each { |target| target.source_build_phase.add_file_reference(ref) }
end
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.resources_build_phase.add_file_reference(project.main_group.new_file('App/Assets.xcassets'))
cave_assets = project.main_group.new_file('Shared/CaveIcons.xcassets')
[app, widget].each { |target| target.resources_build_phase.add_file_reference(cave_assets) }
app.resources_build_phase.add_file_reference(project.main_group.new_file('App/PrivacyInfo.xcprivacy'))
widget.resources_build_phase.add_file_reference(project.main_group.new_file('Widgets/PrivacyInfo.xcprivacy'))
app.resources_build_phase.add_file_reference(project.main_group.new_file('App/CommonFoods.json'))
fonts = project.main_group.new_file('App/Fonts')
fonts.last_known_file_type = 'folder'
[app, widget].each { |target| target.resources_build_phase.add_file_reference(fonts) }
project.targets.each do |target|
  target.build_configurations.each do |config|
    s = config.build_settings
    s['SWIFT_VERSION'] = '5.0'
    s['TARGETED_DEVICE_FAMILY'] = '1'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "com.philstarkovich.cavecals#{target == app ? '' : '.' + target.name}"
    s['MARKETING_VERSION'] = '1.0.3'
    s['CURRENT_PROJECT_VERSION'] = '2'
    s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    s['SUPPORTS_MACCATALYST'] = 'NO'
    s['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    s['SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    s['CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]'] = 'NO'
  end
end
backend_config = project.main_group.new_file('App/Backend.xcconfig')
widget.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'Widgets/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Widgets/QuickLogWidget.entitlements'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Quick Log'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['DEVELOPMENT_TEAM'] = 'J877QX85N5'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end
app.build_configurations.each do |config|
  config.base_configuration_reference = backend_config
  config.build_settings['APP_ATTEST_ENVIRONMENT'] = 'production'
  s = config.build_settings
  s['INFOPLIST_FILE'] = 'App/Info.plist'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'Cave Cals'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  s['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait'
  s['CODE_SIGN_ENTITLEMENTS'] = 'App/CaveCals.entitlements'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
end
tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/CaveCals.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CaveCals'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui.build_configurations.each { |c| c.build_settings['TEST_TARGET_NAME'] = 'CaveCals' }
app.add_system_framework('CloudKit')
app.add_system_framework('AVFoundation')
r = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
r.repositoryURL = 'https://github.com/RevenueCat/purchases-ios.git'
r.requirement = { 'kind' => 'exactVersion', 'version' => '5.88.0' }
project.root_object.package_references << r
%w[RevenueCat RevenueCatUI].each do |name|
  d = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  d.package = r; d.product_name = name
  app.package_product_dependencies << d
  b = project.new(Xcodeproj::Project::Object::PBXBuildFile); b.product_ref = d
  app.frameworks_build_phase.files << b
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui)
scheme.save_as(project.path, 'CaveCals', true)
project.save
