# Some changes for dreamhost based on http://blog.robseaman.com/2008/12/1/deploying-mephisto-with-capistrano-to-dreamhost
# and also on http://railstips.org/2008/12/14/deploying-rails-on-dreamhost-with-passenger

# Load Marley configuration
CONFIG = YAML.load_file( File.join(File.dirname(__FILE__), 'config.yml') ) unless defined? CONFIG

# ----- Setup SSH -------------------------------------------------------------
set :user, "{REPLACE WITH YOUR SSH USERNAME}"
# -----------------------------------------------------------
# set :password, "REPLACE WITH YOUR PASSWORD or USE SSH KEYS"
# -----------------------------------------------------------
# ssh_options[:port] = {SET THIS IF YOU USE NON STANDARD PORT}


# ----- Setup Git -------------------------------------------------------------
default_run_options[:pty] = true #suggested by github to get passphrase prompt
set :runner, "{REPLACE WITH YOUR DH USERNAME}" #who to sudo as for deploy:restart
set :application, "marley"
set :app_path, "{REPLACE WITH YOUR PATH TO YOUR DOMAIN ROOT ON DH}"
set :scm, :git
set :branch, "master" #typical
#set :git_enable_submodules, 1
set :repository,  "{REPLACE WITH YOUR PATH TO YOUR REPOSITORY}"
#set :repository,  "git@github.com:user/marley.git" #github example
set :deploy_via, :remote_cache # "copy" if using local
set :git_shallow_clone, 1 #get the first tree, not all the parents trees - make sure will encompass branch
#set :copy_exclude, [".git", ".gitignore"] #speeds up copy deploy
set :deploy_to, "/home/#{user}/#{app_path}/#{application}"
set :domain, "{REPLACE WITH DOMAIN OF YOUR BLOG}"
set :use_sudo, false

# This is from http://railstips.org/2008/12/14/deploying-rails-on-dreamhost-with-passenger
# Used because in this instance "domain" is different from "application" etc.

# ----- Setup servers ---------------------------------------------------------

server domain, :app, :web
role :db, domain, :primary => true


# ***** No need to change anything below **************************************


# ----- Marley tasks ----------------------------------------------------------

data_directory_name   = CONFIG['data_directory'].split('/').last
remote_data_directory = File.join(deploy_to, data_directory_name)

namespace :sync do
  namespace :setup do
    desc "Set up data directory on remote either by Git-cloning local stuff or cloning from Github"
    task :default do
      Capistrano::CLI.ui.say "Choose how to setup data directory on remote:"
      Capistrano::CLI.ui.choose do |menu|
        menu.prompt = "Choose 1 or 2:"
        menu.choice("By uploading local data") do
          Capistrano::CLI.ui.say("* Setting up data directory on remote by uploading local")
          upload_local
        end
        menu.choice("By cloning Github repository") do
          Capistrano::CLI.ui.say("* Setting up data  directory on remote by cloning Github")
          clone_github
        end
      end
    end
    desc "Set up remote repository on server with post-receive hook for autoupdating content and add remote to yout data repository"
    task :upload_local do
      upload_data_repository
      add_post_receive_hook_for_data_repository
      add_git_remote_to_data_directory
    end
    task :upload_data_repository do
      top.upload(File.join(CONFIG['data_directory'], '.git'), "#{deploy_to}/articles.git" )
      puts "--- Uploaded Git repository from data directory to '#{deploy_to}/articles.git'\n"
      run "cd #{deploy_to}; git clone articles.git #{CONFIG['data_directory'].split('/').last}"
      puts "--- Initialized Git repository\n"
    end
    task :add_post_receive_hook_for_data_repository do
      post_receive_script   = "#{deploy_to}/articles.git/hooks/post-receive"
      hook_command ="export GIT_DIR=.git; cd #{remote_data_directory}; git pull origin master; echo \"[Post-receive] Data directory has been synchronized in #{remote_data_directory}\""
      run "chmod +x #{post_receive_script}; echo '#{hook_command}' >> #{post_receive_script}"
      puts "--- Added post-receive hook for Git repository\n"
    end
    task :add_git_remote_to_data_directory do
      `cd #{CONFIG['data_directory']}; git remote add sync #{user}@#{roles[:app].instance_variable_get(:@static_servers).first.instance_variable_get(:@host)}:#{deploy_to}/articles.git`
      puts "--- Added remote repository 'sync' for data. Use 'git push sync' to synchronize your content.\n"
    end
    desc "Clone Github remote repo in your data directory"
    task :clone_github do
      url = Capistrano::CLI.ui.ask "Enter Github clone URL (you need to setup deploy keys for private repo):"
      run "cd #{deploy_to}; git clone #{url} #{data_directory_name}"
      Capistrano::CLI.ui.say "\n"
      Capistrano::CLI.ui.say "Setup Post-Receive URL hook (http://github.com/guides/post-receive-hooks) in administration for \
                              your Github repository to: http://{YOUR APPLICATION}/sync?token=#{CONFIG['github_token']}"
    end
  end
end

namespace :app do
  desc "Upload configuration file (config/config.yml) to deploy"
  task :upload_config, :roles => :app do
   # Fix directory nesting on server (app is in /DEPLOY/releases/XXX)
   config_yml = File.read( File.join(File.dirname(__FILE__), 'config.yml') ).gsub!(/data_directory: "(.*)"/, 'data_directory: "../\1"')
   File.open( File.join(File.dirname(__FILE__), 'config.remote.yml'), 'w' ) { |f| f << config_yml }
   top.upload('config/config.remote.yml', "#{shared_path}/config.yml" )
  end
  task :create_data_directory do
    run "mkdir -p #{remote_data_directory}"
  end
  task :create_database_for_comments do
    run "cd #{current_path}; rake app:install:create_database_for_comments"
  end
end

namespace :manage do

  namespace :spam do
    desc "Display stats about spam comments in the DB"
    task :stats do
      run "cd #{current_path}; rake manage:spam:stats"
    end
    desc "Delete all spam comments from the DB"
    task :prune do
      run "cd #{current_path}; rake manage:spam:prune"
    end
  end

end

# ----- Hooks ----------------------------------------------------------------

after "sync:setup"   do; app.create_database_for_comments; end
after "deploy:setup" do; app.upload_config; end
after "deploy"       do; deploy.cleanup; end
after "deploy:update_code" do
  run "ln -nfs #{shared_path}/config.yml #{release_path}/config/config.yml"
end

# ----- Over-ride deploy tasks ------------------------------------------------

namespace :deploy do
  
  desc "Deploy new version of application on server"
  task :default, :roles => :app do
    transaction do 
      stop
      update
      restart #changed from start for passenger
    end
  end
  
  desc "Deploy new application on server"
  task :cold do
    update
    restart #changed from start for passenger
  end
  
#  desc "Return to previous version"
#  task :rollback do
#    stop
#    rollback_code
#    start
#  end

  # Changed restart etc for dreamhost/passenger
  desc "Restart passenger."
  task :restart do
    run "touch #{current_path}/tmp/restart.txt"
  end

  [:start, :stop].each do |t|
    desc "#{t} task is a no-op with mod_rails"
    task t, :roles => :app do ; end
  end

end

