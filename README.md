# mt_sync
mt_sync.pl - script for smart transfer Mikrotik/RouterOS configuration from one router to another.

Abilities:
- checking for configuration changes and exiting if no
- calculating differences between configs and tranfserring only changed parts
- skipping or preserving particular configuration sections and statements
- working with standard input/output, files or directly with ssh-enabled routers
- some sanity checking during processing configs

Requirements:
Unix/Linux environment, perl, ssh, sshpass, Algorithm::Diff perl module

Usage:
look at usage.txt

Version: 0.001-20191119
