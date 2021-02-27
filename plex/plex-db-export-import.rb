#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'optparse'
require 'ostruct'
require 'sqlite3'
require 'time'
require 'tty-prompt'

# @param db_path [String]
def repair_database(db_path)
  if File.file?(db_path)
    # check if database is corrupted in a way we can repair
    # @type [SQLite3::Database]
    db = SQLite3::Database.new(db_path)

    integrity_check_output = nil
    begin
      integrity_check_output = db.execute('PRAGMA integrity_check')
    rescue SQLite3::CorruptException => err
      if err.message != 'database disk image is malformed'
        raise "Unable to handle the following database corruption:\n#{err}"
      else
        # continue program
      end
    else
      if (integrity_check_output == 'ok')
        puts 'Database appears to be healthy already!'
        return
      else
        # continue program
      end
    end

    # backup corrupted database in case things break
    backup_database_path = "#{db_path}-#{Time.now.iso8601}"
    FileUtils.copy_file(db_path, backup_database_path)

    # check that backup was made
    raise 'Backing up database failed!' if !File.exist?(backup_database_path)

    # cleanup database so we can operate on it (not sure if this is necessary)
    begin
      db.execute("DELETE from schema_migrations where version='20180501000000'")
    rescue SQLite3::Exception
      # continue
    end
    begin
      db.execute("DROP index 'index_title_sort_naturalsort'")
    rescue SQLite3::Exception
      # continue
    end

    # close original database before dump
    db.close

    # create SQL dump of corrupted database
    # @type [String]
    dump = `echo .dump | sqlite3 "#{db_path}"`
    puts dump.split("\n").last

    # remove original database now that we've got it backed up and dumped
    File.delete(db_path)
    delete_database_tmp_files(db_path)

    if dump.split("\n").last.include?('REVERT')
      # replace REVERT with COMMIT
      # File.write('dump.sql', fixed_dump)
    else
      File.write('dump.sql', dump)
    end

    begin
      `sqlite3 "#{db_path}" < dump.sql`
      File.delete('dump.sql')
      `sudo chown plex:plex "#{db_path}"`
    rescue StandardError => err
      raise err
      File.delete('dump.sql')
    end

    puts 'Hopefully fixed the database!'
  else
    raise "Couldn't find file \"#{db_path}\""
  end
end

def delete_database_tmp_files(db_path)
  File.delete("#{db_path}-shm")
  File.delete("#{db_path}-wal")
end

# @param db_path [String]
def check_database(db_path)
  db = SQLite3::Database.new(db_path)

  if !File.exist?(db_path)
    raise 'Repaired database is missing'
  elsif File.size(db_path) == 0
    raise 'Database is empty'
  elsif db.execute('PRAGMA integrity_check')[0][0] != 'ok'
    raise 'Database failed integrity check'
  end

  # TODO: check if new database is within x% of the size of the old one
end

def start_plex
  puts 'Starting Plex'
  `sudo systemctl start plexmediaserver.service`
  puts 'Started Plex'
end

def stop_plex
  puts 'Stopping Plex'
  `sudo systemctl stop plexmediaserver.service`
  puts 'Stopped Plex'
end

class PlexDBExportImport
  def self.parse(args)
    options = OpenStruct.new
    options.plex_root_path = '/var/lib/plex/Plex Media Server'

    opt_parser =
      OptionParser.new do |opts|
        opts.banner = 'Usage: plex-db-export-import.rb'

        opts.on(
          '--plex-path [PATH]',
          String,
          'Path to Plex root folder'
        ) { |path| options.plex_root_path = path }

        opts.on(
          '-y',
          '--yes',
          'Automatically answer yes to all prompts'
        ) { |auto_accept| options.auto_accept = auto_accept }

        opts.on('-h', '--help', 'Show this message') do
          puts opts
          exit
        end
      end

    opt_parser.parse!(args)
    options
  end
end

def main
  prompt = TTY::Prompt.new
  options = PlexDBExportImport.parse(ARGV)

  if options.auto_accept or
     !prompt.no?(
       'Repair database? This may be destructive! It also requires Plex to be stopped temporarily.'
     )
    db_path =
      "#{
        options.plex_root_path
      }/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    stop_plex
    begin
      repair_database(db_path)
      check_database(db_path)
      delete_database_tmp_files(db_path)
    rescue StandardError => err
      puts err.message
      puts err
      start_plex
      exit 1
    else
      start_plex
      exit 0
    end
  end
end

main
