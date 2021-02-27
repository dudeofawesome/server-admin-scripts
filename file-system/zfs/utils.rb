# @return [Array<String>]
def get_zpools
  # List all zpools
  # -H hides column headers
  `zpool list -H -o name`.split
end
