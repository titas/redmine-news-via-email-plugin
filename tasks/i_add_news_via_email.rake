namespace :i_add_news_via_email do
  desc "Update all changesets - set deployed to true"
  task :deploy_old_changesets => :environment do
    Changeset.all.each do |c|
      c.deployed = true
      c.save
    end
  end

  desc "[Temporal] adds seting :name => :commit_deployed_status_id, :value => 8"
  task :add_custom_settings do
    config = YAML.load_file "#{RAILS_ROOT}/config/settings.yml"
    config.merge!("commit_deployed_status_id" => {"default" => 8})
    File.open("#{RAILS_ROOT}/config/settings.yml", 'w') do |f|
      YAML.dump(config, f)
    end
  end

  desc "Uninstall"
  task :uninstall => :environment do
    # TODO write uninstall - migrations, remove settings (commit_deployed_status_id)
  end

  desc "Install this plugin"
  task :install => :environment do
    migrate = "rake db:migrate_plugins"
    puts "migrate plugins: #{migrate}"
    puts `#{migrate}`
    rake_1_plugin = "rake i_add_news_via_email:deploy_old_changesets"
    puts "rake deploy_old_changesets: #{rake_1_plugin}"
    puts `#{rake_1_plugin}`
    rake_2_plugin = "rake i_add_news_via_email:add_custom_settings"
    puts "rake add_custom_settings: #{rake_2_plugin}"
    puts `#{rake_2_plugin}`
  end
end