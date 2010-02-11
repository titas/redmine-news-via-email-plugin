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
    # TODO write uninstall - migrations, remove settings (commit_deployed_status_id), remove role
  end

  desc "Create Role Deployment-Robo-Reporter with workflow and neccessary permissions
  rake i_add_news_via_email:create_robo_role login=robologin password=robopassword mail=robo_email@gmail.com project=sandbox"
  task :create_robo_role => :environment do
    puts "Login: #{ENV['login']}"
    puts "Password: #{ENV['password']}"
    puts "Email: #{ENV['mail']}"
    puts "project id: #{ENV['project']}"
    robo_role = Role.find_by_name("Deployment-Robo-Reporter")
    if robo_role.nil?
      robo_role = Role.new(:name => "Deployment-Robo-Reporter", :assignable => 0,
        :position => Role.all.length + 1)
      robo_role.save
      Tracker.all.each do |t|
        robo_role.workflows << Workflow.new(:tracker_id => t.id,
          :old_status_id => Setting[:commit_fix_status_id].to_i,
          :new_status_id => Setting[:commit_deployed_status_id].to_i)
      end
      robo_role.permissions = [:manage_news, :edit_issues, :manage_repository]
      robo_role.save
      puts "Robo role save: #{robo_role.save}"
    else
      puts "Role already exists"
    end
    robo_user = User.new(:password => ENV['password'],
      :password_confirmation => ENV['password'], :mail => ENV['mail'])
    robo_user.login = ENV['login']
    robo_user.firstname = "#{ENV['login']} robot"
    robo_user.lastname = "#{ENV['login']} robot"
    puts "Robo user save: #{robo_user.save}"
    project = Project.find_by_identifier(ENV['project'])
    if project
      member = Member.new(:user_id => robo_user.id, :role_id => robo_role.id, :project_id => project.id)
      member.save
      puts "Robo membership save: #{member.save}"
    end
  end

  desc "Install i_add_news_via_email plugin"
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