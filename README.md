# knife-secret

# Requirements

* GPG encrypted encrypted secrets
* knife plugins
  * knife-block - https://github.com/greenandsecure/knife-block
* knife file
  * knife-block - https://github.com/cparedes/knife-file (may become obsolete - knife already provides the fundamental libs to do what this does)
* Gems
  * gpgme - http://rubygems.org/gems/gpgme
  * erubis - http://www.kuwata-lab.com/erubis
  * highline - http://rubygems.org/gems/highline 

***

# Additions to knife.rb

Make sure to add the following to your knife.rb file (this should be a shared location - but nothing prevents it from being managed by an individual)

```ruby
if ::File.exist?(File.expand_path("/opt/ops/etc/knife.company.rb", __FILE__))
  Chef::Config.from_file(File.expand_path("/opt/ops/etc/knife.company.rb", __FILE__))
end
```

# knife.comany.rb

```ruby
company_pass_repo              "#{ENV['HOME']}/.password-store"
company_password_gpg_template  "#{ENV['HOME']}/.password-store/chef/passwords/master_password_list.json.erb.gpg"
company_keys_gpg_template      "#{ENV['HOME']}/.password-store/chef/keys/master_keys_list.json.erb.gpg"
company_secret_gpg_path        "#{ENV['HOME']}/.password-store/chef/secret"
company_filter_environments    %w{development test workstations}
company_password_filter_value  "admin"
company_jenkins_server         "jenkins"
company_jenkins_sync_triggers  ["/buildByToken/build?job=chef-data-bags-users-ssh-key-sync&token=fjw43FOJH2bp3IPpPWaoD7rMU71RoW18q21NYhYilj"]
my_knife_blocks                %w{production aws dev}
```

## What each of these values means:

```company_pass_repo``` - We track the gpg changes in our Git VCS since we use pass this is already built in.  This is the .git location for the GPG store.
```company_password_gpg_template``` - Instead of managing multiple password files (which we have done in the past) we will now manage one master password file and let the tool deal with modifying passwords with a filtered value.
```company_keys_gpg_template``` - Same concept for SSH and SSL keys.  Currently we are considering password hashes here too.. maybe will change.
```company_secret_gpg_path``` - The root directory to your GPG secret files.  Assumes they are named by environment (production, staging, etc...)
```company_environments``` - The environmens your company has defined
```company_filter_environments``` - Environments to filter passwords on with the ```company_filter_values```
```company_filter_value``` - OPTIONAL value: if not used the environments + _admin will become the password otherwise populating this will be the new password values for items in the password data bags for environemtns in the ```company_filter_environments```
```my_knife_blocks``` - This array block defines the knife-block environments that you want to manage with knife-secret.  These will be the environments that keys and passwords get uploaded to with using the --upload flag

# Why?

companies have secrets (passwords and keys for example).  In our environment we tend to store passwords and keys in databags named after each environment.  This provideds a natural 
and optional security boundary if you need different credentials for different environments.  This tool also solves the need for keeping a source of truth for SSL certificates, SSH Keys
as well as passwords outside of chef but integrating it with the tools of chef.  It also comes at a time of transition in our company, our team is growing and becomeing more familiar
with managing chef and this takes the bottle neck off of the people who previously manged it.

knife secret hopefully helps fill some of the gaps that seem to exist in password management in chef and when using multiple chef servers.  Knife tools tend to be very narrow in 
scope which I believe is by design, so this tool just re-uses the libraries of other knife plugins as well as adding some better security features that I have not seen in the community.

Tools like knife-file do a pretty good job at managing encrypted data bags but do not seem to address possible security issues having your chef secret file(s) shared amongst a group.
Now maybe I'm wrong but those file are the keys to the kingdom in any given company so we want to protect these as well as we can, they can provide access to passwords and keys
that normally would not be accessible to someone.  Things like having the "encrypted_data_bag_secret" in mode 0644 or greter will get uploaded to nodes at bootstrap time making the keys 
accessible to anyone and we want tighter security.  This addresses it by keeping the secrets locked away in a gpg store (separate from the chef-repo) that gets pulled out when using this tool and deleted when done.
I do borrow the same concept from knife file, the secrets get stored in the chef-repo encrypted so restores and rollbacks should still have some autonomy as long as the secret file(s) are 
accessible (so keep you gpg store handy).:w

Hopefully this tool will help address these holes while still making them making easy to manage encrypted data bags (passwords and keys as of the plugins inception) and cut out a lot systematic steps and typing.

# Password Filtering:

The tool provides password filtering for selected environments.  It uses the same users accross environments (possible TODO: filter users too) Leaving a single master list to update for 
the different type of data bags.  It also addresses that some passwords need to traverse all environments and can be easily done by droopping "_passthru": true" in a password block to avoid
filtering.

***

# Usage

# Edit password or key templates 
```knife secret edit``` (--passwords|--keys) [--encrypt] [--upload] [--all-chefs]

options:

  ```--passwords``` | ```--keys``` : REQUIRED - (generate passwords for each envrionment) 
  Using this option takes the master list from a gpg store and creates data bags for each environment.  It strips out passwords from seleected environments.  This can also be used
  to verify the data bags before encrypting them.  

  ```--encrypt``` : REQUIRED BY PROCESS - (this encrypts the data bag files in your chef-repo)
  Required by process simply means by not using this you risk checking in unencrypted data bags into chef-repo.  If you do not use this flag, make sure you understand what you are doing.
  This flag is required to make sure passwords are not checked in unencrypted.

  ```--upload``` : OPTIONAL - using this will upload all the environment data bags to the chef server in you knife.rb file

  ```--all-chefs``` : OPTIONAL - (requires --upload flag) this flag will upload the data bags to all the che servers defined in the array 'my_knife_blocks' in your knife.rb files

Common Example(s):

Do everything all at once for a super quick and easy change.  Ultimately this is really what it's about.  Do it all at once!  Generate the passwords, encrypt them, store them in chef-repo,
update the source of truth for keys/passwords (gpg store) and upload the changes to all chef servers defined in your knife.rb (user defined).  The only thing the user is still reponsible for,
is checking in the encrypted data bags into chef-repo, this just provides a nice way of generating them and dropping them into place.

  knife company secrets --passwords --encrypt --upload --all-chefs

  knife company secrets --keys --encrypt --upload --all-chefs

***

# TODO
* build in a flag that helps populate all knife.rb files managed by knife-block with required fields using one block as a template
* auto query environments from chef-repo or server instead of requiring them in knife.rb
