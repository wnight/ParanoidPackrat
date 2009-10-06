=begin
		Copyright 2009 Jeff Welling (jeff.welling (a) gmail.com)
		This file is part of ParanoidPackrat.

    ParanoidPackrat is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    ParanoidPackrat is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with ParanoidPackrat.  If not, see <http://www.gnu.org/licenses/>.
=end
require 'fileutils'

#This module is intended to assist users while they are working with 
#ParanoidPackrat from IRB.  Basically, the executed ./ParanoidPackrat.rb
#file will interact with the IRB library, in a one on top of the other
#fashion.
module PPIrb
	#simpleBackup(backup) performs a simple backup.
	#backup is expected to be the hash from @Configs[name] .
	#It will;
	#	1. create a directory with the name of newDatetime() in the backup/name dir.
	#	2. perform an rsync -a --link-dest=../last_backup backupTarget backup/name/datetime/ .
	#	3. check entire backup/name dir recursively for duplicate files, and hardlink for single instance storage.
	#
	#In that order.  It returns the path that the backup was stored in, for example "/backupDest/backupName/datetime/"
	def self.simpleBackup(backup)
		backup[:BackupDestination]=PPConfig[:globalDests] if backup[:BackupDestination].nil?
		PPCommon.pprint( "simpleBackup():  Performing simple backup, '#{backup[:BackupTarget]}'  to  '#{backup[:BackupDestination].join("', '")}'")
		PPCommon.pprint( "simpleBackup():  Running garbage collection..." )
		PPCommon.pprint( "simpleBackup():  Garbage collection finished, #{PPCommon.gc.to_s} deleted." )
		date=PPCommon.newDatetime
		error=false
		dests=[]

		backup[:BackupDestination].each {|dest|
			PPCommon.makeBackupDirectory(dest) unless (
				File.exist?(dest) and
				File.directory?(dest)
			)

			dest_name=PPCommon.addSlash(dest) + 'backup/' + backup[:BackupName]
			dest_name_date=PPCommon.initBackup(dest, backup[:BackupName])
			err_log=dest_name_date + 'err_log.txt'
			first_or_second=nil

			if PPCommon.containsBackups?(dest, backup[:BackupName]).class==TrueClass
				first_or_second=:first
				PPCommon.pprint('simpleBackup():  Not first time backing up, hardlinking to old backups to save space')
			else
				first_or_second=:second
				PPCommon.pprint('simpleBackup():  First time backing up.')
			end

			# the /1024 is to account for nextBackupWillTake? returning bytes, and df returning 1K blocks, or kilobytes.
			PPCommon.pprint( "simpleBackup():  Calculating space..." )
			PPCommon.pprint( "simpleBackup():  Backup is estimated to take #{guess=(PPCommon.willTakeUp?(backup[:BackupTarget], dest_name_date).to_i / 1024 ) } Kilobytes.\nsimpleBackup():  Available space is  #{actual=PPCommon.getFreeSpace(dest_name_date)} Kilobytes." )
			unless (actual.to_i > guess.to_i)
				PPCommon.pprint("simpleBackup():  Omgpanic!   Available space is #{actual}, but backup is estimated to take #{guess}.")
				PPCommon.pprint("simpleBackup():  Attempting to free some space...\n")
				PPCommon.pprint("simpleBackup():  Expiring old backups...")
				PPCommon.pprint("simpleBackup():  #{PPCommon.expireOldBackups(backup) rescue 0} Expired...")
				unless actual.to_i > guess.to_i
					PPCommon.pprint("simpleBackup(): FAIL - She just can't do it captain!")
					return :fail
				end
				#check for free space? only continue if theres space available.
			end
			PPCommon.rsync( backup[:BackupTarget], dest_name_date, err_log)
			er= PPCommon.rsyncErr?( $?, err_log )
			#maybe a case on the return value of whatWasError?()

			unless er==false  #unless there aren't any, process the errors by asking the user.
				#FIXME This is probly where we'd put the code to store the user response for the long term
				keep_fail=true
				er.each_key {|key|
					if key==:FailedToOpen
						if PPConfig.ignorePermissions?
							keep_fail=false
							next
						end
						er[key].each {|file_that_failed|
							keep_fail=false if PPCommon.prompt("Rsync error:  #{key.to_s}  -  '#{file_that_failed.strip}' \nIgnore this error? (Do not count this as an error, update the last_backup symlink?)")==:yes
						}
					end
				}
				er=false if keep_fail==false
			end

			if er==false
				if first_or_second==:first
					File.unlink( PPCommon.addSlash(dest_name) + 'last_backup')
					File.symlink( dest_name_date, PPCommon.addSlash(dest_name) + 'last_backup' )
					#run the method to scan all of the backups for duplicates and hardlink them
				else
					File.symlink( dest_name_date, PPCommon.addSlash(dest_name) + 'last_backup' )
				end
				PPCommon.removeMark(dest_name_date.gsub(' ', '\ '))
			end
			PPCommon.pprint( "simpleBackup():  Done '#{dest}' with abnormal existatus - rsync gave non-zero exitstatus!\n\t\tBackup was performed, but some files may not have been copies so last_backup still points to your most recent completed backup.\n" ) unless er==false
			PPCommon.pprint( "simpleBackup():  Done '#{dest}'.  Check the log and the backups for bugs and errors." )
			
			dests << dest_name_date
		}
		dests
	end

=begin
	#takes a backup hash, and tries to guess the next backup size using PPCommon.willTakeUp?()
	#NOTE that using only the dry-run method, as we currently do, does not accurately report how much space the backup will take
	#because it seems rsync doesn't account for the space that empty dirs take, 4k.  If you backup something with a lot of empty
	#directories, and you have barely made any changes, then this may return a very small amount for the next backup but with 
	#the size of directories it could easily amount to tens or hundreds of megabytes, in relation to the size of your backup target.
	#returns the estimated size in bytes
	def self.nextBackupWillTake? backup
		source=backup[:BackupTarget]
		destination=(PPCommon.addSlash(backup[:BackupDestination]) + 'backup/' + PPCommon.addSlash(backup[:BackupName]) + 'fake_destination')
		PPCommon.willTakeUp?(source, destination)
	end
=end

	#shrinkBackupDestination(backup,wide) scan backupDestination/backupName/ for duplicates, hardlinking to save space
	#
	#By default, it will only traverse backup directories (backupDest/backupName/datetimes).  To get it to
	#scan every folder, set wide=true. 
	#Regardless of the state of wide, it will not hardlink duplicate files inside the same backup
	#in order to preserve the convention of being able to restore from your backups exactly what you put in; If it were to hardlink
	#duplicates in the same backup then when you restored them you would either have to replace every hardlink'd file with a whole
	#copy of the originional or you would have to restore keeping the hardlinks as they are.  Restoring and keeping the hardlinks
	#as they are would only really be bad because of the potential of forgetting that you've hardlinked every duplicate and then
	#inadvertently changing all when you tried to change one, but a safe default has been chosen to avoid confusion and trouble.
	#
	#Be warned! This is a very dangerous operation if you forget that you've hardlinked
	#to files that are in backupDest/backupName that aren't your backups, and you use this option to hardlink to them, and then
	#you change them, YOU WILL BE CORRUPTING YOUR BACKUPS.  This is why wide=nil by default, but if you know you won't be
	#changing those files it could be useful to hardlink them to save a little bit of space.  
	#
	#Also note there is no undo for
	#this operation, if you run it once, that file is hardlinked and you will have to create a copy, unlink the file, and mv
	#the copy into place for every file thats not in a backupDest/backupName/datetimes dir to undo this operation!
	#
	#	NOTE THIS REQUIRES THAT YOUR BACKUPS ARE ATOMIC - NEVER EDIT YOUR BACKUPS
	def self.shrinkBackupDestination(backup,wide=nil)
		return false #until   "raise "File #{original_file} has changed since hashing!!" unless getFileSignature(original_file) == sig" Doesn't throw an error anymore.
=begin		its throwing this;    (Keep in mind, line numbers may become skewed as commits progress.

/var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/PPCommon.rb:271:in `shrinkBackupDestination': File /var/media/home/jeff/Documents/Projects//ParanoidPackrat/xaa has changed since hashing!! (RuntimeError)
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/PPCommon.rb:264:in `glob'
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/PPCommon.rb:264:in `shrinkBackupDestination'
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/PPIrb.rb:82:in `simpleBackup'
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/ParanoidPackrat.rb:6:in `run'
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/ParanoidPackrat.rb:5:in `each'
        from /var/media/home/jeff/Documents/Projects/ParanoidPackrat/lib/ParanoidPackrat.rb:5:in `run'
        from ./ParanoidPackrat.rb:35

=end
 
		raise "you idiot" unless backup.class==Hash
    sigs = getExistingFileSignatures
    Dir.glob("#{backup[:BackupTarget]}/**/*") {|new_file|
      sig = getFileSignature(new_file)
      unless sigs[sig]
        sigs[sig] = new_file
      else
        original_file = sigs[sig]
        next if original_file == new_file
        raise "File #{original_file} has changed since hashing!!" unless getFileSignature(original_file) == sig
        hardlinkFile(new_file, original_file)
      end
    }
    saveFileSignatures(sigs)
	end
end
