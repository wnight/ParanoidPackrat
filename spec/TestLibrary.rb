require 'rubygems'
require 'facets/integer/of'

class Array
  def random
    entries[rand(length)]
  end
end

module TestLibrary
  #mktempdir(prefix = 'PP') will return a temp directory.
  #This directory is not yet, but should be auto-deleted on exit
  def mktempdir str = 'PP'
    str += '.XXXXXX' unless str =~ /X+$/
    `mktemp -td #{str}`.strip # Is there a better way?
  end
	
  def rand_file_name
    chars = ('a'..'z').collect + ('A'..'Z').collect + ('0'..'9').collect
    name = (rand(6) + 2).of { chars.random }.join
  end

  def create_random_file dir
    `touch '#{dir}/#{rand_file_name}'`
  end

  # Creates a tempdir, recursively populates it, returns a count of files and dirs"
  # No upper bound on size of tempdir created... can be slow
  def build_temp_dir dir = nil
    unless dir # default case
      dir = PPCommon.mktempdir 'PP-test' 
      (rand(5) + 3).times { create_random_file dir } # make more random files in top-level dir
    else
      Dir.mkdir(dir) unless File.exists?(dir) && File.directory?(dir)
    end
    loop do
      case rand(7)
        when (0..4) ; create_random_file dir
        when     5  ; build_temp_dir "#{dir}/#{rand_file_name}"
        else        ; break
      end
    end
    dir
  end

  # Counts the number of files and directories under a given dir
  def entries_under dir
    files = Dir.glob("#{dir}/**/*")
    files << dir
  end

end