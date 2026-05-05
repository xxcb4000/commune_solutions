source "https://rubygems.org"

gem "fastlane", "~> 2.225"

# fastlane plugins (ajouter ici si besoin de play store, slack notifs, etc.)
plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
