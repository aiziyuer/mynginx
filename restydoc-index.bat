@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/env perl
#line 15

use strict;
use warnings;

use FindBin ();
use File::Find ();
use Cwd qw( cwd realpath );
use File::Spec ();
use File::Copy qw( copy );
use File::Path qw( make_path );
use Getopt::Long qw( GetOptions );
use bytes ();

sub shell_quote ($);

GetOptions(
    "outdir=s" => \(my $outdir),
) or die "Usage: $0 [--outdir DIR] DIR\n";

if (!defined $outdir) {
    $outdir = "$FindBin::RealBin/..";

} else {
    $outdir = File::Spec->rel2abs($outdir);
}

$outdir = realpath($outdir);

my $indir = shift
    or die "no input project directory name specified.\n";

if (!-d $indir) {
    die "input directory $indir not found.\n";
}

$indir = File::Spec->rel2abs($indir);

$indir =~ s{/+$}{}g;

(my $full_dist_name = $indir) =~ s{.*/}{};
(my $dist_name = $full_dist_name) =~ s{ [-_] v? ( \d+ (?:\.\d+)* (?: rc\d+ | _\d+ )? ) $ }{}i;
$dist_name = lc $dist_name;
$dist_name =~ s/\.org$//;
my $dist_ver = $1;

#print "name: $full_dist_name\n";
#if (defined $dist_ver) {
    #print "version: $dist_ver\n";
#}

my @aliases = gen_aliases($indir, $dist_name);
#print "aliases: @aliases\n";

my $poddir = "$outdir/pod/$dist_name";
#warn "poddir: $poddir";

if (!-d $poddir) {
    make_path($poddir);
}

my @dist_modules;

File::Find::find(\&wanted,  $indir);

my $index = "dist $dist_name\n";

if ($dist_ver) {
    $index .= "  version $dist_ver\n";
}

if (@aliases) {
    $index .= "  aliases @aliases\n";
}

if (@dist_modules) {
    @dist_modules = sort { lc($a->{name}) cmp lc($b->{name}) } @dist_modules;
    my @names = map { lc($_->{name}) } @dist_modules;
    $index .= "  modules " . join(" ", @names) . "\n";

    for my $module (@dist_modules) {
        $index .= <<_EOC_;

module $module->{name}
_EOC_

        my @aliases = gen_aliases(undef, $module->{name});
        if (@aliases) {
            $index .= "  aliases @aliases\n";
        }

        my $sections = $module->{sections};
        if (defined $sections) {
            for my $sec (@$sections) {
                $index .= "  section $sec->{from} $sec->{to} $sec->{title}\n";
            }
        }
    }
}

$index .= "\n";

my $index_file = "$outdir/resty.index";
open my $out, ">>:encoding(UTF-8)", $index_file
    or die "cannot open $index_file for appending: $!\n";
print $out $index;
close $out;

sub wanted {
    return unless -f $_ && m/ \. ( md | markdown | pod ) $ /x;
    my $ext = lc $1;
    my $docfile = $File::Find::name;

    my $dir = File::Spec->rel2abs($File::Find::dir);

    if ($dir =~ m{^\Q$poddir\E(?:/|$)}) {
        warn "WARNING: ignoring $docfile in outdir.\n";
        return;
    }

    my $name = File::Spec->abs2rel($docfile, $indir);
    return if $name =~ /^node_modules/i;

    $name = lc $name;
    $name =~ s{ ^ (?: lib | src | lua | docs? ) / }{}xi;
    $name =~ s{ \. \w+ $ }{}x;
    $name =~ s{/}{.}g;
    $name =~ s/\.org$//;

    return if length($name) == 1;

    my $podfile;

    if ($name =~ / ^ (?: README | index ) $ /xi) {
        $name = $dist_name;
    }

    if ($ext eq 'pod') {
        $podfile = "$poddir/$name.pod";
        copy($docfile, $podfile)
            or die "cannot copy $docfile to $podfile: $!\n";

    } else {
        my $quoted_mdfile = shell_quote $docfile;

        #warn $name;
        #warn "wanted: $File::Find::dir $File::Find::name $_\n";
        $podfile = "$poddir/$name.pod";
        my $quoted_podfile = shell_quote $podfile;
        #warn "$name => $podfile";
        shell("$FindBin::RealBin/md2pod.pl -o $quoted_podfile $quoted_mdfile");
    }

    my $dist_module = process_pod($podfile, $name);

    push @dist_modules, $dist_module;
}

sub strip_pod_tags {
    my $pod = shift;
    if ($pod =~ /[<>]/) {
        #warn $pod;
        $pod =~ s/E<lt>/&lt;/g;
        $pod =~ s/E<gt>/&gt;/g;
        $pod =~ s/E<middot>/./g;
        $pod =~ s/E<sol>/\//g;
        while ($pod =~ s/\b[CFBI]<([^<>]*)>/$1/g) {}
        $pod =~ s/\&lt;/</g;
        $pod =~ s/\&gt;/>/g;
    }
    $pod;
}

sub process_pod {
    my ($infile, $name) = @_;

    my $dist_module = {
        name => $name,
    };

    open my $in, "<:encoding(UTF-8)", $infile or
        die "cannot open $infile for reading: $!\n";

    my ($toc_level, $new);
    while (<$in>) {
        if (defined $toc_level) {
            if (/ ^ =head (\d+) /x && $1 >= $toc_level) {
                undef $toc_level;
                $new .= $_;
                next;
            }

            # ignore the content
            next;
        }

        # !defined $level

        if (/ ^ =head (\d+) \s+ Table \s+ of \s+ Contents? \s* $ /ix) {
            $toc_level = $1;
            # ignore the content
            next;
        }

        $new .= $_;
    }

    close $in;

    open my $out, ">:encoding(UTF-8)", $infile
        or die "cannot open $infile for writing: $!\n";
    print $out $new;
    close $out;

    open $in, "<:encoding(UTF-8)", $infile or
        die "cannot open $infile for reading: $!\n";

    my @sections;
    my $level;
    while (<$in>) {
        if (/ ^ =head (\d+) \s+ (\S.*) /mx) {
            $level = $1;
            (my $title = $2) =~ s/\s+$//;
            $title = strip_pod_tags($title);
            $title = lc $title;
            $title =~ s/^\s*\d+(\.\d+)*\s+-\s+//;

            next unless $title =~ /[a-z]+/;
            my $len = bytes::length($_);
            my $pos = tell($in) - $len;
            my $sec = {
                title => $title,
                from => $pos,
                level => $level,
            };
            push @sections, $sec;
            next;
        }

        if (/ ^ =item \s+ (\S.*) /mx) {
            (my $title = $1) =~ s/\s+$//;

            next unless defined $level;

            $title = strip_pod_tags($title);
            $title = lc $title;
            $title =~ s/^\s*\*\s*//;
            $title =~ s/["']//g;

            next unless $title =~ /[a-z]+/;

            #warn "section $title";
            my $len = bytes::length($_);
            my $pos = tell($in) - $len;
            my $sec = {
                title => $title,
                from => $pos,
                level => $level + 1,
            };
            push @sections, $sec;
        }
    }

    my $final_pos = tell $in;

    close $in;

    my (%levels, $prev_level);
    for my $sec (@sections) {
        my $level = $sec->{level};
        if (defined $prev_level && $level <= $prev_level) {
            for (my $l = $prev_level; $l >= $level; $l--) {
                my $s = $levels{$l};
                next if !defined $s;
                #warn "setting to...";
                $s->{to} = $sec->{from};
                delete $levels{$l};
            }
        }

        if (defined $prev_level && $levels{$level}) {
            die "Bad level $level";
        }
        $levels{$level} = $sec;
        $prev_level = $level;
    }

    if (defined $prev_level) {
        for (my $l = $prev_level; $l >= 1; $l--) {
            my $s = $levels{$l};
            next if !defined $s;
            #warn "setting to...";
            $s->{to} = $final_pos;
            delete $levels{$l};
        }
    }

    if (%levels) {
        require Data::Dumper;
        die "cannot happen: ", Data::Dumper::Dumper(\%levels);
    }

    if (@sections) {
        $dist_module->{sections} = \@sections;
    }

    return $dist_module;
}

sub shell {
    my $cmd = shift;

    #warn $cmd;
    system($cmd) == 0
        or die "failed to run command \"$cmd\": $!\n";
}

sub gen_aliases {
    my ($indir, $name) = @_;

    $name =~ s/-\d+\.\d+.*//g;

    my @aliases;
    my $alias = $name;
    if ($alias =~ s/-nginx-module$//) {
        $alias =~ s/-/_/g;
        $alias = "ngx_" . $alias;
        push @aliases, $alias;

    } else {
        $alias = $name;
        if ($alias =~ s/^ngx_http_(\w+)_module$/ngx_$1/) {
            push @aliases, $alias;

        } else {
            $alias = $name;
            if ($alias =~ / ^ lua (?: - \w+ )+ $ /x) {
                $alias =~ s/^lua-//;
                $alias =~ s/-/./g;
                push @aliases, $alias;
            }
        }
    }

    if (defined $indir) {
        my $config_file = "$indir/config";
        if (-f $config_file) {
            open my $in, $config_file
                or die "cannot open $config_file for reading: $!\n";
            while (<$in>) {
                if (/ \b ngx_addon_name = .*? (\w+) /x) {
                    my $addon = lc $1;
                    push @aliases, $addon;
                    last;
                }
            }
            close $in;
        }
    }

    return @aliases;
}

sub shell_quote ($) {
    my $ret = shift;

    if (!defined($ret) || $ret eq '') {
        return "''";
    }

    if ($ret =~ /[[:cntrl:]]/s) {
        die "shell_quote(): No way to quote string containing control characters\n";
    }

    $ret =~ s/([#&;`'"|*?~!<>^()\[\]{}\$\\, ])/\\$1/gs;

    return $ret;
}

__END__
:endofperl
