$:.unshift File.expand_path('../../lib', __FILE__)
require 'chef'
require 'chef/knife/block'
require 'erubis'
require 'git'
require 'gpgme'
require 'highline/import'
