It needs to be noted that using this on a backupDestination could 'contaminate' the backupDestination or whichever dir you pass to it in that it would create hardlinks for duplicates where there would otherwise have been two copies of the same file.  This is not huge, but in terms of being able to restore exactly what you commited, this is breaks it.