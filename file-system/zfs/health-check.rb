#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'utils'

# # zpool status monkey
#   pool: monkey
#  state: ONLINE
# status: One or more devices has experienced an error resulting in data
#         corruption.  Applications may be affected.
# action: Restore the file in question if possible.  Otherwise restore the
#         entire pool from backup.
#    see: http://www.sun.com/msg/ZFS-8000-8A
#  scrub: scrub completed after 0h0m with 8 errors on Tue Jul 13 13:17:32 2010
# config:

#         NAME        STATE     READ WRITE CKSUM
#         monkey      ONLINE       8     0     0
#           c1t1d0    ONLINE       2     0     0
#           c2t5d0    ONLINE       6     0     0

# errors: 8 data errors, use '-v' for a list

# @param pool_name [String]
def check_pool_for_errors(pool_name)
  # @type [String]
  zpool_status = `zpool status "#{pool_name}"`
  if zpool_status.include?("errors: No known data errors")
    puts "no error"
  elsif zpool_status.match(/^errors: /)
    puts "uh oh!"
  else
    raise "Unrecognized state"
  end
end

# Checks pool usage to see if the 80% threshold is surpassed.
# Using over 80% of a disk can cause severe performance penalties.
# @param pool_name [String]
def check_pool_usage(pool_name)
  pool_capacity = `zpool list -H -o cap "#{pool_name}"`
end

def check_smart
  # `sudo smartctl --quietmode=errorsonly --all /dev/disk/by-id/#{disk_id}`
end

def main
  check_pool_for_errors("storage")
end

main()
