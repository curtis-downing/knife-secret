# secrets edit
# pretty sure this is more complicated than it should be
# in hind sight including knife-file is actually pretty useless since it appears
# it's all in knife and chef encrypted libraries anyway so... we'll tidy this up
# in the near future
# for now it solves some imeediate problems that plague us right meow
# managing keys and passwords just got super easy while maintaining a some security
# I'm sure with a little planning this could be cleaned up significantly
# TODO: pull the gpg encrypt/decrypt options in definitions


require "chef/knife"

module Company
  class SecretEdit < Chef::Knife

    deps do
      require 'chef/json_compat'
      require 'chef/knife/core/object_loader'
      require "chef/knife/block"
      require 'erubis'
      require 'git'
      require 'gpgme'
      require 'highline/import'
    end

    banner "knife secret edit (options)"

    attr_accessor :data_bag_structure

    def init
      self.config = Chef::Config.merge!(config)
      @my_chef_repo = "#{config[:cookbook_path][0]}/.." # knife.rb supports multiple chef repos: assuming index 0 is primary, others are upstream 
      if config[:upload]
        bl = GreenAndSecure::BlockList.new
        @my_current_block = bl.current_server
      end

      # make sure users knife.rb file has required config options
      ui.fatal "Missing #{ui.color("company_password_gpg_template", :cyan)} path from your local knife.rb"  if ! config[:company_password_gpg_template]
      ui.fatal "Missing #{ui.color("company_keys_gpg_template", :cyan)} path from your local knife.rb"      if ! config[:company_keys_gpg_template]
      ui.fatal "Missing #{ui.color("company_filter_environments", :cyan)} path fromr you local knife.rb"    if ! config[:company_filter_environments]
      ui.fatal "Missing #{ui.color("company_secret_gpg_path", :cyan)} path from your local knife.rb"        if ! config[:company_secret_gpg_path]

      # currently we only deal with passwords or keys
      # this could be more generic to accomodate different data bags ... in fact it should!
      if config[:passwords] 
        @file_type = "passwords"
        @gpg_master_list = config[:company_password_gpg_template]
        @my_data_bag_path = "#{@my_chef_repo}/data_bags/passwords"
      elsif config[:keys]
        @file_type = "keys"
        @gpg_master_list = config[:company_keys_gpg_template]
        @my_data_bag_path = "#{@my_chef_repo}/data_bags/keys"
      else
        abort("Must specify the data bag type you wish to edit")
      end

      @our_environments = Dir.entries("#{@my_chef_repo}/environments").delete_if { |x| x =~ /^.$/ || x =~ /^..$/ || x =~ /README.md/ }.map {|x| x.gsub(/.json/, "")}
      @company_gpg_store_path = config[:company_pass_repo]
      @fs_mode         = 0600 #only this user should have access to these files
      @tmp_master_list = "#{ENV['HOME']}/.chef/tmp_#{@file_type}_master_list.json"
      @tmp_master_list_compare = "#{ENV['HOME']}/.chef/tmp_#{@file_type}_master_list_compare"
      @secret_file = "#{ENV['HOME']}/.chef/tmp_secret_file"

      # even though I've allwoed the setting of a gpg pass in a users knife config it is not recommended unless the file is properly secured
      # for now the intent is to use highline to gather the password and maybe we'll consider this okay when the company plugins enforce secure
      # file permissions (so don't use this config optino in your knife.rb ... yet)
      # also.. I think I saw somewhere in the gpgme classes a cipher that does a password read.. maybe it can replace highline?
      @my_gpg_pass = config[:my_gpg_pass] || ask("Enter shared password to decrypt:  ") { |q| q.echo = "*" }
    end

    option :passwords,
      :short => "-p",
      :long => "--passwords",
      :description => "manage password(s)"

    option :keys,
      :short => "-k",
      :long => "--keys",
      :description => "edit key(s)"

    option :upload,
      :short => "-u",
      :long => "--upload",
      :description => "upload data bag(s) to chef server(s)",
      :boolean => true | false,
      :default => false

    option :encrypt,
      :short => "-e",
      :long => "--encrypt",
      :description => "encrypt data bag(s) in your chef-repo vcs",
      :boolean => true | false,
      :default => false

    option :generate,
      :short => "-g",
      :long => "--generate",
      :description => "generate unencrypted data bags in your chef-repo vcs",
      :boolean => true | false,
      :default => false

    option :all_chefs,
      :short => "-A",
      :long => "--all-chefs",
      :description => "all chef environments manged by knife-block and identified by 'my_knife_blocks' array in your local knife.rb files (this means all your knife.rf files)",
      :boolean => true | false,
      :default => false

    def gpg_decrypt_master_list
      crypto = GPGME::Crypto.new :armor => true
      master_list = File.open(@tmp_master_list,"w")
      crypto.decrypt File.open(@gpg_master_list), :password => @my_gpg_pass, :output => master_list
      master_list.close
      #create comparison file for later diffing
      FileUtils.cp @tmp_master_list, @tmp_master_list_compare
    end

    def edit_master_list
      @loader ||= Chef::Knife::Core::ObjectLoader.new(Chef::DataBagItem, ui)
      item = @loader.object_from_file(@tmp_master_list)
      output = edit_data(item)

      f = File.open(@tmp_master_list, "w")
      f.sync = true
      f.puts Chef::JSONCompat::to_json_pretty(output)
      f.close
    end

    def run
      self.init
      self.gpg_decrypt_master_list
      self.edit_master_list

      if config[:generate]
        self.generate_all_envs_from_file
      end

      if config[:encrypt]
        self.generate_all_envs_from_file
        self.encrypt_all_env_files
      end

      if config[:upload]
        self.upload_all_data_bag_files
      end

      # update gpg store if changes were made
      self.gpg_encrypt_master_list

      # delete temporary files
      File.delete(@secret_file) if File.exists?(@secret_file)
      File.delete(@tmp_master_list) if File.exists?(@tmp_master_list)
      File.delete(@tmp_master_list_compare) if File.exists?(@tmp_master_list_compare)
    end

    def upload_all_data_bag_files
      if config[:upload] 
        if config[:all_chefs] # swtich to block in config
          knife_block = GreenAndSecure::BlockUse.new
          config[:my_knife_blocks].each do |block|
            knife_block.name_args = [block]
            knife_block.run
            self.configure_chef # reload configs from the changed knife.rb fiile
            self.upload_all_environment_data_bags
          end

          # take us back to the knife block we we started with so as not to confuse people
          knife_block.name_args = [@my_current_block]
          knife_block.run
        else
          self.upload_all_environment_data_bags
        end
      end
    end

    def upload_all_environment_data_bags
      @our_environments.each do |env|
        self.upload_data_bag(@file_type,env)
      end
    end

    def upload_data_bag(data_bag_name, environment)
      # for some rason "knife file decrypt" and "data bag" with the "--all" flag
      # do not work so; this really re-inventing the wheel and it's also really annoying 
      dbff = DataBagFromFile.new
      dbff.name_args = [data_bag_name, "#{@my_data_bag_path}/#{environment}.json"]
      dbff.run
    end

    def git_gpg_store
      puts "Updating gpg password store git repo" 
      # this should probably go into a new def
      git = Git.open(@company_gpg_store_path)
      git.pull #make sure we have the latest changes
      git.add(:all=>true)  
      git.commit("updated #{@file_type} data bags")
      git.push
    end

    def encrypt_all_env_files
      if config[:encrypt]

        fe = FileEncrypt.new 
        #originally got it working this way - replacing with gpg decrypt 
        #fe.config[:file] = "/etc/chef/encrypted_data_bag_secret"
        # encrypt each file
        @our_environments.each do |env|
          self.get_chef_secret_by_environment(env)
          fe.config[:secret_file] = @secret_file
          ui.info("#{ui.color("ENCRYPTING", :magenta)} #{@file_type} data bag:  #{ui.color("#{env}.json", :magenta)}")

          item_path = "#{@my_data_bag_path}/#{env}.json"
          secret = fe.read_secret
          item = fe.loader.object_from_file(item_path)
          item = Chef::EncryptedDataBagItem.encrypt_data_bag_item(item, secret)
          #output(format_for_display(item.to_hash))
          file_output = format_for_display(item.to_hash)


          self.save_all_env_files(file_output,env)
        end

      #remind users to check in the new data bags! 
      ui.info("chef-repo has been updated: #{ui.color("YOU MUST CHECK IN THE #{@file_type} DATA BAGS", :red)}")
      end
    end

    def gpg_encrypt_master_list
      # apply changes to the master list in gpg store if there are any diffs between the files
      if ! FileUtils.compare_file(@tmp_master_list,@tmp_master_list_compare)
        ui.info("Updating GPG store with latest #{ui.color("#{@file_type} master list", :yellow)}")
        crypto = GPGME::Crypto.new
        mf = File.open(@tmp_master_list, "r")
        encrypted_data = crypto.encrypt mf, :symmetric => true, :password => @my_gpg_pass
        ef = File.open(@gpg_master_list, "w")
        ef.write(encrypted_data)
        ef.close
        mf.close
        self.git_gpg_store
      end
    end

    def generate_all_envs_from_file
      f_template = File.read(@tmp_master_list)
      erb_template = Erubis::Eruby.new(f_template)
      @our_environments.each do |env|
        ui.info("generating #{ui.color("DECRYPTED", :green)} #{@file_type} file:  #{ui.color("#{env}.json", :green)}")
        @data_bag_structure = JSON.parse(erb_template.result(:environment => env))
        if config[:company_filter_environments].include?(env)
          # only do this for passwords
          if config[:passwords]
            self.filter_passwords(env)
          end
        end
        self.save_all_env_files(@data_bag_structure,env)
      end
    end

    def filter_passwords(environment)
      #if not defined, password is env + _admin so test would be "test_admin" (password replacements)
      filtered_passwords = config[:company_password_filter_value] || environment + "_admin"
      @data_bag_structure.each do |unit,db_config|
        # I'm pretty sure this is wrong in so many ways but time is short
        # passwords and keys and mutltiple chef servers make it too much for one person to manage, so...  suck it samwise -Archer
        if db_config.is_a? Hash
          unless db_config.has_key?("_passthru")
            db_config.each do |k,v|
              if unit != 'id' #ignore id
                v.replace(filtered_passwords)
              end
            end
          end
        end
      end
    end

    def save_all_env_files(data,env)
      #structures = JSON.parse(template.result(:environment => env))
      #there is probably a btter method tucked away in on of the knife classes... so look around
      #need to make sure perms only allow current user!!!!!! so doeet
      File.open("#{@my_data_bag_path}/#{env}.json","w") do |f|
        f.write(JSON.pretty_generate(data))
      end
    end

    def get_chef_secret_by_environment(environment)
      if config[:encrypt]
        crypto = GPGME::Crypto.new :armor => true
        gpg_f = "#{config[:company_secret_gpg_path]}/#{environment}.gpg"
        f = File.open(@secret_file, "w")
        crypto.decrypt File.open(gpg_f), :password => @my_gpg_pass, :output => f
        f.chmod(@fs_mode)
        f.close
      end
    end

  end
end
