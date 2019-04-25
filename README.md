# nBackup

A [simple](https://en.wikipedia.org/wiki/KISS_principle) Bash script for making local backups with different views.

## Why

Obviously there are [a lot](https://github.com/n1trux/awesome-sysadmin#backups) of backup solutions that already exist. None of them met my requirements or were far more complicated than I need. I am a fan of the [KISS principle](https://en.wikipedia.org/wiki/KISS_principle) and feel backups shouldn't be complex because then recovery is complicated and you don't want complex when shit's hit the fan and you need to recover critical data urgently.

## Features

-   **dependency-less** - backups can be copied to a new system and restored without having to install a slew of programs/dependencies
-   **browsable in 3 ways** - backups can be viewed/browsed in three different ways right from the command-line:
    1.   **current** - the current version of the backup
    1.   **snapshot-in-time folders** - if you want to view/restore all the data from a specific backup
    1.   **running file versions** - if you want to quickly view previous versions of a specific file
-   **delete old backups** - old backups can be deleted based on an `and` or `or` combination of:
    1.   `count` - keep at least this many old backups
    1.   `minimum age` - keep old backups that are newer than this many seconds, minutes, hours, days, weeks, months, or years
-   **e-mail status** - status/output sent to e-mail
-   **speed over space** - storage is cheap, processing time is not; there is no compression, tarring, or encryption (For my use-case, after `nBackup` takes a backup, I use https://rclone.org to send encrypted copies to my public cloud storage solution.)

## How It Works

This script implements the ideas covered [here](http://www.mikerubel.org/computers/rsync_snapshots/) and [here](http://www.admin-magazine.com/Articles/Using-rsync-for-Backups/%28offset%29). I won't go into the details here -- read the articles if you're curious, but at a high level, the script works by making `rsync` backups of your data, then using hard-links to identify different versions. By using hard-links you save on space by only saving new copies of files if they have changed.


## Example End Result

Assuming your source folder looks like so:

 - `source`
   - `file 001` (inode # 10)
   - `file 002` (inode # 20)
   - `file 003` (inode # 30)

And you do the following:

1. take a backup
1. delete `source/file 003`, add `source/file 004`, take a backup
1. modify `source/file 002`, add some new files to `source/folder 100`, take a backup

This is how your backup folder would look:

 - `backup`
   - `20190101` -- first backup
     - `source`
       - `file 001` (inode # 10)
       - `file 002` (inode # 20)
       - `file 003` (inode # 30)
   - `20190201` -- second backup; deleted `source/file 003` and added `source/file 004`
     - `source`
       - `file 001` (inode # 10)
       - `file 002` (inode # 20)
       - `file 004` (inode # 40)
   - `20190301` -- third backup; modified`source/file 002` and added some new files to `source/folder 100`
     - `source`
       - `file 001` (inode # 10)
       - `file 002` (inode # **21**) -- points to a different file than the previous backups
       - `file 004` 
       - `folder 100`
         - `file 005` (inode # 50)
         - `file 006` (inode # 60)
   - `current`
     - `source`
       - `file 001` (inode # 10)
       - `file 002` (inode # **21**) -- points to the most recent version of the file
       - `file 004` (inode # 40)
       - `folder 100`
         - `file 005` (inode # 50)
         - `file 006` (inode # 60)
   - `combined`
     - `source`
       - `file 001.20190101` (inode # 10)
       - `file 002.20190101` (inode # **20**)
       - `file 002.20190201` (inode # **21**) -- notice there are two versions of this file in the same folder so you can quickly find the one you want
       - `file 003.20190101` (inode # 30)
       - `file 004.20190201` (inode # 40)
       - `folder 100`
         - `file 005.20190301` (inode # 50)
         - `file 006.20190301` (inode # 60)

Notice how the files share a common `inode`. This is because, since the file(s) didn't change, they point to the same file. When a file changes, the old versions point to the original and the new version points to a new file. This saves a lot of space.

Note: The actual file/folders will include date/time stamp but I have removed the time for this example. You can customize the date/time format you want to use.