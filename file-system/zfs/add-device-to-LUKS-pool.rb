#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'ostruct'
require 'tty-prompt'

require_relative 'utils'

KEYFILE_DIR = '/var/lib/zfs-encryption/keys'

class Something
  def self.parse(args)
    options = OpenStruct.new

    opt_parser =
      OptionParser.new do |opts|
        opts.banner = 'Usage: add-device-to-LUKS-pool.rb'

        opts.on('-h', '--help', 'Show this message') do
          puts opts
          exit
        end
      end

    opt_parser.parse!(args)
    options
  end
end

def get_drive_dev_map
  # Map all devs to ATA drive device IDs
  ls_out =
    `
      ls -la /dev/disk/by-id/ | grep "\\Wata-.*[a-zA-Z]\$" | awk '{print substr($11,7),$9}'
    `.split("\n")
  Hash[ls_out.map { |k, _v| [k.split[0], k.split[1]] }]
end

# @return [Array<String>]
def get_drive_devs
  # List all ATA drive devices by ID
  `
    ls -la /dev/disk/by-id/ | grep "\\Wata-.*[a-zA-Z]\$" | awk '{print $9}'
  `.split
end

# @return [Array<String>]
def get_devs_in_zpool(pool_name)
  # Get zpool status and cut up to get devs
  # -P shows full device path
  # @type [Array<String>]
  zpool_devs =
    `
      zpool status -P "#{pool_name}" | grep -P '\\t  /dev/' | awk '{print $1}'
    `.split
    .map { |dev|
      if dev.start_with?("/dev/disk/by-id/")
        dev.split("/dev/disk/by-id/")[1].split("-part1")[0].strip
      else
        dev.strip
      end
    }

  if zpool_devs.any? { |i| i.start_with?('/dev/mapper/') }
    drive_dev_map = get_drive_dev_map

    zpool_devs = zpool_devs.map { |dev|
      if dev.start_with?('/dev/mapper/')
        device_mapper_id = `realpath "#{dev}"`.strip.split('/dev/')[1]
        block_dev_id = `ls "/sys/block/#{device_mapper_id}/slaves/"`.strip

        drive_dev_map[block_dev_id]
      else
        dev
      end
    }
  end

  zpool_devs
end

def cryptsetup_luksformat(pool_name, dev_id)
  keyfile = "#{KEYFILE_DIR}/#{pool_name}.key"
  gen_luks_key(keyfile) unless File.file?(keyfile)

  `
    cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/disk/by-id/
    "#{dev_id}"
    "#{keyfile}"
  `
end

def cryptsetup_luksopen(pool_name, dev_id)
  devs_in_pool = get_devs_in_zpool(pool_name).count
  command = %(cryptsetup luksOpen "/dev/disk/by-id/#{dev_id}"
    "#{pool_name}#{devs_in_pool}_crypt")
  puts "Make sure to mount device at boot with '#{command}'"
  `#{command}`
end

# @param keyfile_path [String]
def gen_luks_key(keyfile_path)
  puts "Make sure to backup your new keyfile: '#{keyfile_path}'"
  `dd if=/dev/urandom of="#{keyfile_path}" bs=1024 count=4`
end

# @param pool_name [String]
# @param dev_path [String] fully qualified device path
def add_dev_to_zpool(pool_name, dev_path)
  `zpool add "#{pool_name}" "#{dev_path}"` 
end

def main
  prompt = TTY::Prompt.new
  options = Something.parse(ARGV)

  selected_zpool = prompt.select('Select zpool', get_zpools)

  selected_devs = nil
  while selected_devs.nil? || selected_devs.size <= 0
    puts 'No drives selected!' unless selected_devs.nil?
    used_devs = get_zpools.map{ |pool| get_devs_in_zpool(pool) }.flatten
    unused_devs = get_drive_devs.select { |dev| !used_devs.include?(dev) }
    selected_devs =
      prompt.multi_select('Select drive', unused_devs, per_page: 10)
  end

  puts "Are you sure you want to format and add the following drives to the " +
    "ZFS \"#{selected_zpool}\" pool?"
  puts
  puts selected_devs.map { |dev| "  #{dev}"}
  puts
  puts "YOU WILL LOSE ALL DATA CURRENTLY ON THEM!"

  if prompt.no?("Wipe and add drives to pool?")
    puts "Stopping"
    exit
  else
    puts "Adding #{selected_devs.join(', ')} to #{selected_zpool}"

    for dev in selected_devs do
      cryptsetup_luksformat(selected_zpool, dev)
      cryptsetup_luksopen(selected_zpool, dev)
    end
  end
end

main()
# puts get_drive_dev_map
# puts get_devs_in_zpool('backup')
