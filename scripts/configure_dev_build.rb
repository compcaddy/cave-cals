# Adds a second installed identity to the existing targets; source membership stays shared.
require 'xcodeproj'

module CaveCalsDevBuild
  def self.configure(project)
    ([project] + project.targets).each do |owner|
      %w[Debug Release].each do |base|
        original = owner.build_configurations.find { |c| c.name == base }
        name = "Dev #{base}"
        config = owner.build_configurations.find { |c| c.name == name }
        unless config
          config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
          config.name = name
          owner.build_configuration_list.build_configurations << config
        end
        config.build_settings = Marshal.load(Marshal.dump(original.build_settings))
        config.base_configuration_reference = original.base_configuration_reference
        settings = config.build_settings
        conditions = Array(settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] || '$(inherited)')
        settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = (conditions + ['CAVE_CALS_DEV']).uniq
        next if owner == project
        suffix = owner.name == 'CaveCals' ? '' : ".#{owner.name}"
        settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.philstarkovich.cavecals.dev#{suffix}"
        case owner.name
        when 'CaveCals'
          settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Cave Cals Dev'
          settings['CODE_SIGN_ENTITLEMENTS'] = 'App/CaveCalsDev.entitlements'
          settings['CAVE_URL_SCHEME'] = 'cavecals-dev'
        when 'QuickLogWidget'
          settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Quick Log Dev'
          settings['CODE_SIGN_ENTITLEMENTS'] = 'Widgets/QuickLogWidgetDev.entitlements'
        end
      end
    end
    app = project.targets.find { |t| t.name == 'CaveCals' }
    app.build_configurations.select { |c| %w[Debug Release].include?(c.name) }.each do |config|
      config.build_settings['CAVE_URL_SCHEME'] = 'cavecals'
    end
    scheme = Xcodeproj::XCScheme.new
    scheme.add_build_target(app)
    scheme.set_launch_target(app)
    project.targets.select { |t| %w[ECCTests ECCUITests].include?(t.name) }.each { |t| scheme.add_test_target(t) }
    scheme.launch_action.build_configuration = 'Dev Debug'
    scheme.test_action.build_configuration = 'Dev Debug'
    scheme.analyze_action.build_configuration = 'Dev Debug'
    scheme.profile_action.build_configuration = 'Dev Release'
    scheme.archive_action.build_configuration = 'Dev Release'
    scheme.save_as(project.path, 'Cave Cals Dev', true)
  end
end

if $PROGRAM_NAME == __FILE__
  project = Xcodeproj::Project.open(File.expand_path('../CaveCals.xcodeproj', __dir__))
  CaveCalsDevBuild.configure(project)
  project.save
end
