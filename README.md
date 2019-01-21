# nBackup

nBackup is a simple bash script for making versioned backups of your data where versions are browsable as both snapshot-in-time folders and running file versions

## How It Works

This script implements the ideas covered [here](http://www.mikerubel.org/computers/rsync_snapshots/) and [here](http://www.admin-magazine.com/Articles/Using-rsync-for-Backups/%28offset%29). I won't go into the details here -- read the articles if you're curious, but at a high level, the script works by making `rsync` backups of your data, then using hard-links to identify different versions. By using hard-links you save on space by only saving new copies of files if they have changed.

`nBackup` will create two views of your data:

 1. **snapshot-in-time folders** - if you want to view/restore all the data from a specific backup
 2. **running file versions** - if you want to quickly view previous versions of a specific file

## Example End Result

Assuming your source folder looks like so:

 - `source`
   - `file 001`
   - `file 002`
   - `file 004` 
   - `folder 100`
     - `file 005`
     - `file 006`

(Note: `source/file 003` is missing because it was deleted after a backup was made.)

Then, after a few backups to `/backup` this is what you'll end up with:

(Note, actual file/folders will include date/time stamp but I have removed the time for this example. You can customize the date/time format you want to use.)

 - `backup`
   - `20190101` -- first backup
     - `source`
       - `file 001`
       - `file 002`
       - `file 003`
   - `20190201` -- second backup; deleted `source/file 003` and created `source/file 004`
     - `source`
       - `file 001`
       - `file 002`
       - `file 004` 
   - `20190301` -- third backup; created `source/folder 100` and modified `source/file 002`
     - `source`
       - `file 001`
       - `file 002`
       - `file 004` 
       - `folder 100`
         - `file 005`
         - `file 006`
   - `current`
     - `source`
       - `file 001`
       - `file 002`
       - `file 004` 
       - `folder 100`
         - `file 005`
         - `file 006`
   - `combined`
     - `source`
       - `file 001.20190101`
       - `file 002.20190101`
       - `file 002.20190201` -- notice there are two versions of this file in the same folder so you can quickly find the one you want
       - `file 003.20190101`
       - `file 004.20190201` 
       - `folder 100`
         - `file 005.20190301`
         - `file 006.20190301`

You can't see it in the example, but files that were not changed during each backup all point to the same file to save space. 
