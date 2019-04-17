# nBackup

nBackup is a simple bash script for making versioned dependency-less backups of your data where versions are browsable as current backups, snapshot-in-time folders, and running file versions.

[TOC]

## How It Works

This script implements the ideas covered [here](http://www.mikerubel.org/computers/rsync_snapshots/) and [here](http://www.admin-magazine.com/Articles/Using-rsync-for-Backups/%28offset%29). I won't go into the details here -- read the articles if you're curious, but at a high level, the script works by making `rsync` backups of your data, then using hard-links to identify different versions. By using hard-links you save on space by only saving new copies of files if they have changed.

`nBackup` will create three views of your data:

1. **current** - the current version of the backup
1. **snapshot-in-time folders** - if you want to view/restore all the data from a specific backup
1. **running file versions** - if you want to quickly view previous versions of a specific file

## Why and My Requirements

Obviously there are [a lot](https://github.com/n1trux/awesome-sysadmin#backups) of backup solutions that already exist. None of them met my requirements or were far more complicated than I need. I am a fan of the [KISS principle](https://en.wikipedia.org/wiki/KISS_principle) and feel backups shouldn't be complex because then recovery is complicated and you don't want complex when shit's hit the fan and you need to recover critical data urgently.

My requirements:

-   **dependency-less backups and restores** -- I wanted backups that I could copy to a new system and restore without having to first install a slew of programs/dependencies.
-   **speed over space** -- storage is cheap, processing time is not. I wanted to do straight file copies without compressing, tarring, or encrypting. My backups are then encrypted to the cloud using https://rclone.org/.
-   **browsable** -- I wanted backups that I could browse in three different ways ([see How It Works](#how-it-works)).

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
