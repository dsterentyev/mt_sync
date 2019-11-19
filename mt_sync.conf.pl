#!/usr/bin/perl

#master router params
$master_ip = '10.32.255.13';                    # ip
$master_ssh_login = 'conf_sync';                # login
$master_ssh_password = 'some-P@sS\/\/0Rcl';     # password    
$master_ssh_port = 52222;                       # ssh port
$master_ssh_args = '';                          # additional parameters for ssh

#slave router params
$slave_ip = '10.32.255.14';                     # ip
$slave_ssh_login = 'conf_sync';                 # login
$slave_ssh_password = 'some-P@sS\/\/0Rcl';      # password
$slave_ssh_port = 52222;                        # ssh port
$slave_ssh_args = '';                           # additional parameters for ssh

#configuration statements with comment included this line will be ignored
$protective_comment = '[nosync]';               

#configuration statements started with it will be ignored
%branches_ignored = (
    'interface ethernet' => 1,
    'interface vrrp' => 1,
    'system identity' => 1,
    'tool' => 1,
    'user' => 1,
    'system' => 1
);

#configuration branches in which order of statements will be preserved
%branches_ordered = (
    'ip firewall filter' => 1,
    'ip firewall nat' => 1,
    'ip firewall mangle' => 1,
    'ip route rule' => 1
    #need populate all such branches
);

#directory in which will be stored previous configs of master router
$old_configs_dir = ".";

1;
