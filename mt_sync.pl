#!/usr/bin/perl

#toggle it to 0 if you want use external ssh and sshpass
my $use_internal_ssh = 2;

#use Data::Dump qw/dump/;
use Digest::SHA qw/sha512_hex/;
use Algorithm::Diff qw(diff);
if($use_internal_ssh == 1)
{
    use Net::SSH::Perl;
}
elsif($use_internal_ssh == 2)
{
    use Net::SSH2;
}

#don't edit this, use instead command line args or config file
$master_ip = '';
$master_ssh_login = '';
$master_ssh_password = '';
$master_ssh_port = 22;
$master_ssh_args = '';
$slave_ip = '';
$slave_ssh_login = '';
$slave_ssh_password = '';
$slave_ssh_port = 22;
$slave_ssh_args = '';
$protective_comment = '';
%branches_ignored = ();
%branches_force_included = ();
%branches_method_set = ();
%branches_ordered = ();
$old_configs_dir = '.';
@ignored_notes = ();

$conf = shift @ARGV || &help;

#loading configuration
require $conf if $conf ne '-';

#overrides config values by argv
my %args = ();
while(my $arg = shift @ARGV)
{
    if($arg =~ /^-(\w+)\=(.+)$/)
    {
        my $parm = $1;
        my $pvalue = $2;
        if   ( $parm eq 'mip')         { $master_ip = $pvalue; }
        elsif( $parm eq 'mlogin')      { $master_ssh_user = $pvalue; }
        elsif( $parm eq 'mpass')       { $master_ssh_password = $pvalue; }
        elsif( $parm eq 'mport')       { $master_ssh_port = $pvalue; }
        elsif( $parm eq 'msshargs')    { $master_ssh_args = $pvalue; }
        elsif( $parm eq 'sip')         { $slave_ip = $pvalue; }
        elsif( $parm eq 'slogin')      { $slave_ssh_user = $pvalue; }
        elsif( $parm eq 'spass')       { $slave_ssh_password = $pvalue; }
        elsif( $parm eq 'sport')       { $slave_ssh_port = $pvalue; }
        elsif( $parm eq 'ssshargs')    { $slave_ssh_args = $pvalue; }
        elsif( $parm eq 'mconf')       { $args{$parm} = $pvalue; }
        elsif( $parm eq 'sconf')       { $args{$parm} = $pvalue; }
        elsif( $parm eq 'outconf')     { $args{$parm} = $pvalue; }
        elsif( $parm eq 'pcomment')    { $protective_comment = $pvalue; }
        elsif( $parm eq 'ibranches')   { foreach my $karg (split(/,/, $pvalue)) { $branches_ignored{$karg} = 1; }}
        elsif( $parm eq 'obranches')   { foreach my $karg (split(/,/, $pvalue)) { $branches_ordered{$karg} = 1; }}
        elsif( $parm eq 'fbranches')   { foreach my $karg (split(/,/, $pvalue)) { $branches_force_included{$karg} = 1; }}
        elsif( $parm eq 'oldconfdir')  { $old_configs_dir = $pvalue; }
        elsif( $parm eq 'force')       { $args{$parm} = $pvalue; }
        elsif( $parm eq 'sshverbose')  { $args{$parm} = $pvalue; }
        elsif( $parm eq 'quietdiff')   { $args{$parm} = $pvalue; }
        else                           { die "unknown argument $parm passed!\n"; }
    }
    else
    {
        die ("wrong argument $arg passed!\n");
    }
}

#config lines sorted by sections
%mbranches = ();
%sbranches = ();

#array with properly order of sections
@brorder = ();
#all sections in both configs
%brorder = ();
#detected branch actions
%bactions = ();

#line numbers mapping for sections of slave config (for exclusion of [nosync] lines)
%line_nums_map = ();
#line numbers mapping for sections of master config (for exclusion of [nosync] lines)
%line_nums_map_m = ();

#retrieve master router config
my $mconfig;
if(defined $args{'mconf'})
{
    #read from file
    if($args{'mconf'} ne '-')
    {
        $mconfig = prefilter_config(file_get_contents($args{'mconf'}), 1);
    }
    #read from STDIN
    else
    {
        my @lines = ();
        while(<>)
        {
            chomp;
            push(@lines, $_);
        }
        $mconfig = prefilter_config(\@lines, 1);
    }
}
else
{
    #retrieve from router via ssh
    $mconfig = prefilter_config(read_config($master_ip, $master_ssh_login, $master_ssh_password, $master_ssh_port, $master_ssh_args), 1);
}
$mconfig2 = filter_config($mconfig, \%branches_ignored, $protective_comment, \%mbranches, 0, \%branches_force_included);

if(! defined $args{'force'})
{
    `/usr/bin/touch $old_configs_dir/old_$master_ip.conf.sha512`;
    $old_config = file_get_contents("$old_configs_dir/old_$master_ip.conf.sha512");

    if($old_config->[0] eq sha512_hex(join("\n", @$mconfig2)))
    {
        print "none changed in config of $master_ip since last run, exiting\n" if ! defined $args{'quietdiff'};
        exit(0);
    }
}

#retrieve slave router config
my $sconfig;
if(defined $args{'sconf'})
{
    #read from file
    if($args{'sconf'} ne '-')
    {
        $sconfig = prefilter_config(file_get_contents($args{'sconf'}), 0);
    }
    elsif($args{'sconf'} eq '-' && defined $args{'mconf'} && $args{'mconf'} eq '-')
    {
        die("trying get both master and slave configs from STDIN!\n");
    }
    #read from STDIN
    else
    {
        my @lines = ();
        while(<>)
        {
            chomp;
            push(@lines, $_);
        }
        $sconfig = prefilter_config(\@lines, 0);
    }
}
else
{
    #retrieve from router via ssh
    $sconfig = prefilter_config(read_config($slave_ip, $slave_ssh_login, $slave_ssh_password, $slave_ssh_port, $slave_ssh_args), 0);
}

#dump($sconfig);

filter_config($sconfig, \%branches_ignored, $protective_comment, \%sbranches, 1, \%branches_force_included);

#dump(%line_nums_map_m);
#dump(%line_nums_map);

#check branches actions
foreach (keys %bactions)
{
    if(scalar(keys %{$bactions{$_}}) > 1)
    {
        if(! defined defined $bactions{$_}->{'set'} || ! defined defined $bactions{$_}->{'set'})
        {
            die "unknown actions found in branch $_ : " . join(',', keys %{$bactions{$_}}) . "\n";
        }
    }
    if(defined $bactions{$_}->{'set'})
    {
        $branches_method_set{$_} = 1;
        if(defined $branches_ordered{$_})
        {
            die("branch $_ marked as ordered but 'set' action found!\n");
        }
    }
    elsif(! defined $bactions{$_}->{'add'})
    {
        die "unknown action found in branch $_: " . join('', keys %{$bactions{$_}}) . "\n";
    }
}

#mikrotik commands for apply changes
my @cmds = ();

#comments to commands
my @cmdcs = ();

#compare slave and master config section by section
foreach $section (@brorder)
{
    #skip ignored branches
#    next if defined($branches_ignored{$section}) && ! defined($branches_force_included{$section});
#    print "$section \n";
    my $ordered = defined($branches_ordered{$section}) ? 1 : 0;
    #process ordered branch
    if($ordered == 1)
    {
        #create empty set of lines for diff
        $mbranches{"$section:add"} = [] if ! defined $mbranches{"$section:add"};
        $sbranches{"$section:add"} = [] if ! defined $sbranches{"$section:add"};
        #performing diff between slave and master for section
        $sdiff = diff($sbranches{"$section:add"}, $mbranches{"$section:add"});
        if(scalar(@$sdiff) != 0)
        {
            #dump($sdiff);
            #print "------------------------------------------------\n";
            #iterate diff array
            my $ldiff = 0;
            my %didx = ();
        
            my $delta = 0;
            foreach my $hunk (@$sdiff)
            {
                foreach my $change (@$hunk)
                {
                    my ($op, $pos, $data) = @$change;
                    #print "pos:$pos delta:$delta op:$op data:$data\n";
                    #remove config line
                    if ($op eq "-")
                    {
                        my $dlnum = $pos + $delta;
                        my $dlnum2 = $line_nums_map{"$section:add"}->[$dlnum];
                        push(@cmdcs, "\n\# removing ordered: $data");
                        $cmd = "\/$section remove [ :pick [ \/$section find where ! (dynamic || default || builtin)] $dlnum2 ]";
                        &line_nums_map_fix("$section:add", $dlnum, -1);
                        $delta--;
                    }
                    #adding config line
                    elsif ($op eq "+")
                    {
                        my $dlnum = $pos;
                        my $dlnum2 = $line_nums_map{"$section:add"}->[$dlnum];
                        $last_line = $dlnum >= scalar(@{$line_nums_map{"$section:add"}}) ? 1 : 0;
                        push(@cmdcs, "\n\# adding ordered:");
                        $cmd = $data . ($last_line ? '' : " place-before=[:pick [\/$section find where ! (dynamic || default || builtin)] $dlnum2 ]");
                        $delta++;
                        &line_nums_map_fix("$section:add", $dlnum, 1);
                    }
                    #something wrong
                    else
                    {
                        die "unknown operation: \"$op\"\n";
                    }
                    push(@cmds, $cmd);
                }
            }
        }
    }
    #process unordered branch
    else
    {
        #--------------------------#
        # process 'add' statements #  
        #--------------------------#

        #counts unique lines in configs
        my %slnums = ();
        my %mlnums = ();
        @cmdcs2 = ();
        for(my $c = 0; $c < scalar(@{$mbranches{"$section:add"}}); $c++)
        {
            my $key = $mbranches{"$section:add"}->[$c];
            $mlnums{$key} = 0 if ! defined $mlnums{$key};
            $mlnums{$key}++;
        }
        for(my $c = 0; $c < scalar(@{$sbranches{"$section:add"}}); $c++)
        {
            my $key = $sbranches{"$section:add"}->[$c];
            $slnums{$key} = 0 if ! defined $slnums{$key};
            $slnums{$key}++;
        }
        #checking for lines exists in only one config 
        my @addlist = ();
        my @dellist = ();
        for(my $c = 0; $c < scalar(@{$mbranches{"$section:add"}}); $c++)
        {
            push(@addlist, $c) if ! defined $slnums{$mbranches{"$section:add"}->[$c]};
        }
        for(my $c = 0; $c < scalar(@{$sbranches{"$section:add"}}); $c++)
        {
            if(defined $mlnums{$sbranches{"$section:add"}->[$c]} && $mlnums{$sbranches{"$section:add"}->[$c]} > 0)
            {
                $mlnums{$sbranches{"$section:add"}->[$c]}--;
            }
            else
            {
                push(@cmdcs2, $sbranches{"$section:add"}->[$c]);
                push(@dellist, $line_nums_map{"$section:add"}->[$c]);
            }
        }
        #removing lines
        foreach my $c (reverse @dellist)
        {
            my $cmd = "\/$section remove [ :pick [ \/$section find where ! (dynamic || default || builtin) ] $c ]";
            push(@cmdcs, "\n\# removing: " . pop(@cmdcs2));
            push(@cmds, $cmd);
        }
        #adding lines
        foreach my $c (@addlist)
        {
            push(@cmdcs, "\n\# adding:");
            push(@cmds, $mbranches{"$section:add"}->[$c]);
        }

        #--------------------------#
        # process 'set' statements #  
        #--------------------------#

        #create empty set of lines for diff
        $mbranches{"$section:set"} = [] if ! defined $mbranches{"$section:set"};
        $sbranches{"$section:set"} = [] if ! defined $sbranches{"$section:set"};

        if(join("\n", @{$mbranches{"$section:set"}}) ne join("\n", @{$sbranches{"$section:set"}}))
        {
            #simple replace config with all lines without deletion
            foreach my $cmd (@{$mbranches{"$section:set"}})
            {
                push(@cmdcs, "\n\# setting:");
                push(@cmds, $cmd);
            }
        }
    }
}

#putting result config
#to STDOUT
if(defined $args{'outconf'} && $args{'outconf'} eq '-')
{
    print join("\n", @cmds);
    print "\n" if scalar(@cmds) > 0;
}
#to file
elsif(defined $args{'outconf'})
{
    file_put_contents($args{'outconf'}, \@cmds);
}
#to slave router via ssh
else
{
    if($use_internal_ssh == 1)
    {
        $ssh = Net::SSH::Perl->new($slave_ip, options => [ "Port $slave_ssh_port", "Protocol 2", "MACs +hmac-sha1", "debug" ] ) or die "error: ssh failed to connect $ip!\n";
        $ssh->login($slave_ssh_login, $slave_ssh_password) or die "error: ssh failed to authenticate on $ip!\n"; 
        my $cnt = 0;
        foreach my $cmd (@cmds)
        {
            print shift(@cmdcs) . "\n" if defined $args{'sshverbose'};
            print "[$cnt] $cmd\n" if defined $args{'sshverbose'};
            my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
            if($exit != 0 || $stderr ne '' || $stdout ne '')
            {
                print "error $exit while executing command:\n$cmd\n$stdout$stderr\n\n";
            }
            $cnt++;
        }
    }
    elsif($use_internal_ssh == 2)
    {
        my $ssh2 = Net::SSH2->new();
        $ssh2->connect($slave_ip, $slave_ssh_port) or $ssh2->die_with_error("error: ssh failed to connect $ip!\n");
        $ssh2->auth_password($slave_ssh_login, $slave_ssh_password) or $ssh2->die_with_error("error: ssh failed to authenticate on $ip!\n");
        my $cnt = 0;
        foreach my $cmd (@cmds)
        {
            print shift(@cmdcs) . "\n" if defined $args{'sshverbose'};
            print "[$cnt] $cmd\n" if defined $args{'sshverbose'};
            my($stdout, $stderr, $exit) = netssh2cmd($ssh2, $cmd);
            if($exit != 0 || $stderr ne '' || $stdout ne '')
            {
                print "error $exit while executing command:\n$cmd\n$stdout$stderr\n\n";
            }
            $cnt++;
        }
        $ssh2->disconnect;
    }
    else
    {
        my $cmd = "/usr/bin/ssh -T $slave_ssh_args -p $slave_ssh_port $slave_ssh_login\@$slave_ip";
        if($slave_ssh_password ne '')
        {
            $ENV{'SSHPASS'} = $slave_ssh_password;
            $cmd = "/usr/bin/sshpass -e $cmd";
        }
        open SSHPIPE,"| $cmd" or die('can not put resulting config to slave router via ssh!');
        my $cnt = 0;
        foreach my $cmd (@cmds)
        {
            print shift(@cmdcs) . "\n" if defined $args{'sshverbose'};
            print "[$cnt] $cmd\n" if defined $args{'sshverbose'};
            print SSHPIPE "$cmd\n";
            $cnt++;
        }
        close SSHPIPE;
    }
}

#save config of master router for future comparison
if(! defined $args{'outconf'})
{
    file_put_contents("$old_configs_dir/old_$master_ip.conf.sha512", [ sha512_hex(join("\n", @$mconfig2)) ] );
}

#done
0;

#shifts line numbers map [lines without protective comments] -> [all lines]
sub line_nums_map_fix
{
    my $sect = $_[0];
    my $frow = $_[1];
    my $offs = $_[2];
    $arr = $line_nums_map{$sect};
    my $c;
    #delete item in line numbers map
    if($offs == -1)
    {
        splice(@$arr, $frow, 1);
        for($c = $frow; $c < scalar(@$arr); $c++)
        {
            $arr->[$c]--;
        }
        $line_nums_map{"$sect:all"}--;
    }
    #insert item into line numbers map
    elsif($offs == 1)
    {
        if($frow < scalar(@$arr))
        {
            splice(@$arr, $frow, 0, $arr->[$frow]);
        }
        else
        {
            push(@$arr, $line_nums_map{"$sect:all"} - 1);
        }
        for(my $c = $frow + 1; $c < scalar(@$arr); $c++)
        {
            $arr->[$c]++;
        }
        $line_nums_map{"$sect:all"}++;
    }
}

#filter config (remove comments, ignored branches and lines with protective comment)
#and also builds list of branches and line numbers maps
sub filter_config
{
    my $conf = $_[0];
    my $brref = $_[3];
    my @filtered = ();
    $re_filter = join('|', keys %{$_[1]});
    $re_unfilter = join('|', keys %{$_[5]});
#    print "$re_filter\n";
#    print "$re_unfilter\n";
    #section line number counter
    my $scnt2 = 0;
    my $scnt2s = 0;
    my $oldbr = '';
    foreach my $ln (@$conf)
    {
        #check for excluded sections
        if($re_filter ne '' && $ln =~ /^\/($re_filter)/ && ($re_unfilter eq '' || $ln !~ /^\/($re_unfilter)/))
        {
#            print "ignore found: $ln\n";
            next;
        };
        my $parsed = parse_line($ln);
        my $br = $parsed->{'_branch'};
        #reset counter on beginning of new section
        $scnt2 = 0 if $oldbr ne $br;
        $scnt2s = 0 if $oldbr ne $br;
        $oldbr = $br;
        my $action = $parsed->{'_action'};
        #checking for set / add
        if(! defined $bactions{$br})
        {
            my %ahash = ();
            $bactions{$br} = \%ahash;
        }
        $bactions{$br}->{$action} = 1;
            
        #checking for [nosync] comment in config line
        $scnt2++ if $action eq 'add';
        $scnt2s++ if $action eq 'set';
        if($_[2] ne '' && defined $$parsed{'comment'} && index($$parsed{'comment'}, $_[2]) >= 0)
        {
            #skip line for master config
            next;
        }
        push(@filtered, $ln);
        #create section if not exists
        if(! defined $brref->{"$br:$action"}) 
        {
            $brref->{"$br:$action"} = [] ;
            $line_nums_map{"$br:$action"} = [] if $_[4] == 1;
            $line_nums_map_m{"$br:$action"} = [] if $_[4] == 0;
        }
        #save config line to properly section
        push(@{$brref->{"$br:$action"}}, $ln);
        #preserve properly order of sections
        if(! defined $brorder{$br})
        {
            push(@brorder, $br);
            $brorder{$br} = 1;
        }
        #line number section mapping for [nosync] exclusion
        if($action eq 'add')
        {
            if($_[4] == 1)
            {
                push(@{$line_nums_map{"$br:$action"}}, $scnt2 - 1);
                $line_nums_map{"$br:$action:all"} = $scnt2;
            }
            else
            {
                push(@{$line_nums_map_m{"$br:$action"}}, $scnt2 - 1);
                $line_nums_map_m{"$br:$action:all"} = $scnt2;
            }

        }
        elsif($action eq 'set')
        {
            if($_[4] == 1)
            {
                push(@{$line_nums_map{"$br:$action"}}, $scnt2 - 1);
                $line_nums_map{"$br:$action:all"} = $scnt2;
            }
            else
            {
                push(@{$line_nums_map_m{"$br:$action"}}, $scnt2 - 1);
                $line_nums_map_m{"$br:$action:all"} = $scnt2;
            }
        }
    }

    return(\@filtered);
}

#read config from ssh 
sub read_config
{
    my $ip = $_[0];
    my $user = $_[1];
    my $pass = $_[2];
    my $port = $_[3];
    my $sshargs = $_[4];
    if($use_internal_ssh == 1)
    {
        $ssh = Net::SSH::Perl->new($ip, options => [ "Port $port", "Protocol 2", "MACs +hmac-sha1", "debug" ] ) or die "error: ssh failed to connect $ip!\n";
        $ssh->login($user, $pass) or die "error: ssh failed to authenticate on $ip!\n"; 
        my($stdout, $stderr, $exit) = $ssh->cmd('/export compact terse');
        if($exit != 0 || $stderr ne '')
        {
            die "error $exit while exporting config!\n$stdout$stderr\n";
        }
        my @lines = split(/\r\n/, $stdout);
        return(\@lines);
    }
    elsif($use_internal_ssh == 2)
    {
        my $ssh2 = Net::SSH2->new();
        $ssh2->connect($ip, $slave_ssh_port) or $ssh2->die_with_error("error: ssh failed to connect $ip!\n");
        $ssh2->auth_password($slave_ssh_login, $slave_ssh_password) or $ssh2->die_with_error("error: ssh failed to authenticate on $ip!\n");
        my($stdout, $stderr, $exit) = netssh2cmd($ssh2, '/export compact terse');
        $ssh2->disconnect;
        if($exit != 0 || $stderr ne '')
        {
            die "error $exit while exporting config!\n$stdout$stderr\n";
        }
        my @lines = split(/\r\n/, $stdout);
        return(\@lines);
    }
    my $cmd = "/usr/bin/ssh $sshargs -p $port $user\@$ip '/export compact terse'";
    if($pass ne '')
    {
        $ENV{'SSHPASS'} = $pass;
        $cmd = "/usr/bin/sshpass -e $cmd";
    }
    my @lines = `$cmd`;
    if ($? != 0) {
        die "error: ssh on $ip failed to execute $!\n";
    }    
    return(\@lines);
}

#skip notes and combine multiline statements into single line
#also checking for errors
sub prefilter_config
{
    my $contl = '';
    my $c = 0;
    my @conf = ();
    my $bline;              # last line that start from /
    my $ncnt = 0;           # counter of lines that started from /
    my $bscnt = 0;          # counter of lines that not started from /
    foreach (@{$_[0]})
    {
        chomp;
        if($c == 0)
        {
            if(! /^\# (\w{3}\/\d{2}\/\d{4} \d{2}:\d{2}:\d{2}) by RouterOS/)
            {
                die("error: router $ip not returned RouterOS config timestamp: $_\n"); 
            }
        }
        $c++;
        if(/^\#/)
        {
            if($ncnt > 0 && $_[1] == 1)
            {
                $ignored_note_found = 0;
                foreach $ignmsg (@ignored_notes)
                {
                    $ignored_note_found = 1 if /^\#\s*$ignmsg/;
                }
                next if $ignored_note_found == 1;
                warn("In section '$bline' of master router config found followed RouterOS note: \n\$_\n");
                die("Possible config is in inconsistent state. Unpredictable results may occurs, stopping work\n");
            }
            next;
        };
        s/^\s+//;
        s/\s+$//;
        #check for multiline statement
        if(! /^\// && $contl eq '')
        {
            $_ = "$bline $_";
            if($bscnt == 0)
            {
                pop(@conf);
                $bscnt++;
            }
        }
        else
        {
            $bline = $_;
            $bscnt = 0;
            $ncnt++;
        }
        my $cont = /\\\s*$/ ? 1 : 0;
        if($cont)
        {
            s/\\\s*$//;
            $contl .= $_;
        }
        else
        {
            push(@conf, $contl . $_);
            $contl = '';
        }
    }
    return(\@conf);
}

#split single line to branch, action and parameters
sub parse_line
{
    my $line =  $_[0];
    my %vals = ();
    $_ = $line;
    if(s/^\/([\d\w\- ]+)\s+(add|set)\s*$// || s/^\/([\d\w\- ]+)\s+(add|set)\b\s+//)
    {
        $vals{'_branch'} = $1;
        $vals{'_action'} = $+;
        $vals{'_params'} = $_;
        my $params = $_;
        my $st = 0; 
        my $ch = '';
        my $pch = '';
        my $vkey = '';
        my $vval = '';
        my $quot = 0;
        my $rquot = 0;
        for(my $c = 0; $c <= length($params); $c++)
        {
            $pch = $ch;
            $ch = substr($params, $c, 1);
            if($st == 0 && $quot == 0 && $ch eq '[')
            {
                $quot = 1;
                $vkey = '';
            }
            elsif($st == 0 && $quot == 1 && $ch eq ']')
            {
                $quot = 0;
                $vkey =~ s/^\s+//;
                $vkey =~ s/\s+$//;
                $vals{3} = $vkey if $vkey ne '';
                $vkey = '';
            }
            elsif($st == 0 && $quot == 1)
            {
                $vkey .= $ch;
            }
            elsif($st == 0 && $ch eq '=')
            {
                $st = 1;
                $vval = '';
            }
            elsif($st == 0 && $ch eq ' ')
            {
                $vals{$vkey} = '' if $vkey ne '';
                $vkey = '';
            }
            elsif($st == 0)
            {
                $vkey .= $ch;
            }
            elsif($st == 1 && $quot == 0 && $ch eq '"')
            {
                $quot = 1;
            }
            elsif($st == 1 && $quot == 1 && $rquot == 0 && $ch eq "\\")
            {
                $rquot = 1;
                $vval .= $ch;
            }
            elsif($st == 1 && $quot == 1 && $rquot == 1 && $ch =~ /[0-9A-F]/)
            {
                $rquot = 2;
                $vval .= $ch;
            }
            elsif($st == 1 && $quot == 1 && $rquot == 1 && $ch =~ /[\"\\nrt\$\?\_abfv]/)
            {
                $rquot = 0;
                $vval .= $ch;
            }
            elsif($st == 1 && $quot == 1 && $rquot == 1)
            {
                die("error: can't parse single char quote (in pos $c) in $params\n");
            }
            elsif($st == 1 && $quot == 1 && $rquot == 2 && $ch =~ /[0-9A-F]/)
            {
                $rquot = 0;
                $vval .= $ch;
            }
            elsif($st == 1 && $quot == 1 && $rquot == 2)
            {
                die("error: can't parse double char quote (in pos $c) in $params\n");
            }
            elsif($st == 1 && $quot == 1 && $ch eq '"')
            {
                $quot = 0;
            }
            elsif($st == 1 && $quot == 1 && $ch eq ' ')
            {
                $vval .= $ch;
            }
            elsif($st == 1 && $ch eq ' ')
            {
                $vals{$vkey} = $vval;
                $st = 0;
                $vkey = '';
                $vval = '';
            }
            else
            {
                $vval .= $ch;
            }
        }
        $vals{$vkey} = $vval if $vkey ne '';
    }
    else
    {
        die("error: can't parse: $line\n");
    }
    return(\%vals);
}

#save array of strings to file
sub file_put_contents
{
    open FILE,">$_[0]" or die "error: can not open file $_[0] for write";
    foreach my $ln (@{$_[1]})
    {
        print FILE "$ln\n";
    }
    close FILE;
}

#load array of strings from file
sub file_get_contents
{
    my @fcontent;
    open FILE,"$_[0]" or die "error: can not open file $_[0]";
    while(<FILE>)
    {
        chomp;
        push(@fcontent, $_);
    }
    close FILE;
    return(\@fcontent);
}

sub netssh2cmd
{
	my $ssh2 = $_[0];
	my $cmd = $_[1];
	my @result = ();
	my $ssherr = '';
	my $chan = $ssh2->channel() or $ssh2->die_with_error;
#	print "executing $cmd \n";
    $chan->exec($cmd) or $ssh2->die_with_error;
	my ($out, $err) = ('', '');
    while (! $chan->eof) 
    {
        if (my ($o, $e) = $chan->read2) 
        {
            $out .= $o;
            $err .= $e;
        }
        elsif($ssh2->error != 0) 
        {
            $ssh2->die_with_error("netssh2cmd: can not retieving result while executing $cmd \n");
        }
    }
	my $exit = $chan->exit_status;
    $chan->close;
    return ($out, $err, $exit);
}

#help message
sub help
{
    print 'Script for smart transfer RouterOS configuration from one router to another

usage:
./mt_sync.pl [configfile] [-arg1=somevalue] ... [-argN=somevalue]
    configfile   - name of file with configuration variables or \'-\' 
                   (which means starting without reading config file)
    arg1 .. argN - optional arguments that overrides variables 
                   in config file
                   
list of command line arguments:
    -mip         - ip address of router from which configuration will be taken
    -mlogin      - login of such router 
    -mpass       - password of such router (if exists)
    -mport       - tcp port of such router (default value is 22)
    -msshargs    - optional arguments for ssh of such router (e.g. ssh key)
    -sip         - ip address of router to which configuration will be saved
    -slogin      - login of such router
    -spass       - password of such router (if exists)
    -sport       - tcp port of such router (default value is 22)
    -ssshargs    - optional arguments for ssh of such router (e.g. ssh key)
    -mconf       - confiuration of master router will be taken from file 
                   instead of router (or from STDIN if passed \'-\')
    -sconf       - confiuration of slave will be taken from file instead 
                   of router (or from STDIN if passed \'-\')
    -outconf     - resulting lines will be saved to file instead of router 
                   (or to STDIN if passed \'-\')
    -pcomment    - protective comment (configuration lines which contains 
                   comment included this value will be ignored by script)
    -ibranches   - list of configuraion branches which will be ignored by 
                   script (quoted by single quotes and separated by comma)
    -fbranches   - list of configuraion branches which will be not ignored 
                   even if presents in ignore list (quoted by single quotes 
                   and separated by comma)
    -obranches   - list of branches in which order of lines will be preserved
                   (quoted by single quotes and separated by comma)
    -force       - don\'t compare current and previous configuration 
    -oldconfdir  - override direcory for storing previous configurations 
                   (default is current direcory)
    -sshverbose  - show commands during transfer config to router via ssh 
    -quietdiff   - no message about no changes in config since last run 
';
    exit(0);
}
