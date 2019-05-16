#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'ostruct'

require 'tty-prompt'

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

def get_drive_devs
  # List all ATA drive devices by ID
  `
    
    ls -la /dev/disk/by-id/ | grep "\\Wata-.*[a-zA-Z]\$" | awk '{print $9}'

  `.split
end

def get_zpools
  # List all zpools
  # -H hides column headers
  `zpool list -H -o name`.split
end

def get_devs_in_zpool(pool_name)
  # Get zpool status and cut up to get devs
  # -P shows full device path
  zpool_devs =
    `zpool status -P #{pool_name} | grep -P '\\t  ' | awk '{print $1}'`.split

  if zpool_devs.any? {|i| i.start_with?('/dev/mapper/')}
    puts 'uses mapped drives'
    drive_dev_map = get_drive_dev_map
    mapped_devs =
      Hash[
        `
          dmsetup deps -o devname |
            awk '{print substr($1,0,length($1)-1),substr($5,2,length($5)-2)}'
        `.split("\n")
          .map { |k, _v| [k.split[0], drive_dev_map[k.split[1]]] }
      ]
  end
end

def cryptsetup_luksformat(pool_name, dev_id)
  keyfile = "#{KEYFILE_DIR}/#{pool_name}.key"
  gen_luks_key(keyfile) unless File.file?(keyfile)

  `
    cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/disk/by-id/
      #{dev_id}
      #{keyfile}
  `
end

def cryptsetup_luksopen(pool_name, dev_id)
  `cryptsetup luksOpen /dev/disk/by-id/#{dev_id} #{pool_name}0_crypt`
end

def gen_luks_key(keyfile_path)
  `dd if=/dev/urandom of=#{keyfile_path} bs=1024 count=4`
end

def main
  prompt = TTY::Prompt.new
  options = Something.parse(ARGV)

  selected_zpool = prompt.select('Select zpool', get_zpools)

  selected_drives = nil
  while selected_drives.nil? || selected_drives.size <= 0
    puts 'No drives selected!' unless selected_drives.nil?
    selected_drives =
      prompt.multi_select('Select drive', get_drive_devs, per_page: 10)
  end

  puts "Adding #{selected_drives.join(', ')} to #{selected_zpool}"
end

# main()
# puts get_drive_dev_map
puts get_devs_in_zpool('backup')
