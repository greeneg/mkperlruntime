#!/usr/bin/env perl

use strict;
use warnings;
use English;
use utf8;

use feature qw(
    lexical_subs
    say
    signatures
);
no warnings 'experimental::lexical_subs';
no warnings 'experimental::signatures';

use Cwd;
use Getopt::Long qw(:config gnu_compat);
use Archive::Tar;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Temp qw(tempdir tempfile);
use FindBin;
use Digest::MD5 qw(md5);
use Net::Domain qw(hostname hostdomain);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Term::ANSIColor;
use User::pwent;

use lib "$FindBin::Bin/lib";

use os;
use pkglib;

# This script uses sudo to install both Perl, and all the modules. It requires
# password-less sudo to do its work.
#
# Remember to export any proxy variables that you might need for internet
# access, as this script pulls down packages from CPAN

# get the OS we're running under
my $os = os->new();
my $platform = $os->os_platform();
my $distribution = $os->os_family($platform);
my $os_release = $os->os_release($platform);

my $perl_version = '';
my $email_address = undef;

my sub download ($title, $url) {
    say color('bold magenta'). "$title from $url" . color('bold blue');
    system("curl -O --progress-bar $url");
    print color('reset');
}

my sub chksum_file ($file, $signatures_file) {
    open(my $md5sum_file, $signatures_file) or
      die "Cannot open file! $!";
    my $md5sum = readline($md5sum_file);
    close $md5sum_file;

    print color('bold cyan') . "Checking MD5 sum of files: ";
    open(my $fh, $file) or
      die "Cannot open file! $!\n";
    my $checksum = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh;

    unless ("$checksum" eq "$md5sum") {
        say color('bold white on_red') . "Checksum does not match! Exiting" . 
          color('reset');
        exit -1;
    } else {
        say color('bold green'). "OK" . color('reset');
    }
}

my sub file_type ($file) {
    return 'tar.gz';
}

my sub unpack_tar_gz ($file) {
    # check that file is a tar.gz
    unless (file_type($file) eq 'tar.gz') {
        say STDERR color('bold white on_red') .
          "File is not a tar.gz file type. Cannot continue!" .
          color('reset');
        exit -1;
    }

    print color('bold cyan') . "Unpacking '$file': " . color('reset');
    my (undef, $file_postfix) = split(/(.*\.tar)/, $file);
    my $status = gunzip $file => $file_postfix or
      die color('bold white on_red') . "Cannot uncompress tar.gz file! $?\n" .
        color('reset');
    my $tar = Archive::Tar->new();
    $tar->read($file);
    $tar->list_files();
    $tar->extract();
    say color('bold green') . "DONE" . color('reset');
}

my sub write_file ($file, @content) {
    open(my $fh, ">", $file) or
      die color('bold white on_red') . "Cannot open file: $file! $?\n" .
          color('reset');
    foreach my $line (@content) {
        print $fh $line;
    }
    close $fh;
}

my sub parse_version ($perl_version) {
    my ($maj_version, $min_version, $patch_version) = split('.', $perl_version);

    return ($maj_version, $min_version, $patch_version);
}

my sub process_build_config($perl_version, $file) {
    my ($maj_version, $min_version, $patch_version) = parse_version($perl_version);
    my (undef, $filename) = tempfile(OPEN => 0);

    my $file_base = basename($file);

    say color('bold cyan') .
      "Generating '$file_base' for Perl version $perl_version here: $filename" .
      color('reset');
    my @content;

    my $pw = getpwuid($EUID);
    my $username = $pw->name;
    my $hostname = hostname();
    my $domainname = hostdomain();
    $domainname =~ s/^\.//; # trim off any leading '.'
    open(my $fh, $file) or
      die color('bold white on_red') . "Cannot open file: $file! $?\n" .
          color('reset');
    foreach my $line (readline $fh) {
        $line =~ s/%PREFIX%/\/opt\/Perl-$perl_version/g;
        $line =~ s/%VERSION%/$perl_version/g;
        $line =~ s/%MINOR%/$min_version/g;
        $line =~ s/%PATCH%/$patch_version/g;
        $line =~ s/%EMAIL%/$email_address/g;
        $line =~ s/%USER%/$username/g;
        $line =~ s/%HOSTNAME%/$hostname/g;
        $line =~ s/%DOMAIN%/$domainname/g;

        push(@content, $line);
    }
    close $fh;

    write_file($filename, @content);

    return $filename;
}

my sub build_perl ($perl_version, $parent_dir, $os_family, $os_release, $temp_dir) {
    # process config file for the version we're installing
    my %files;
    my $instruct_file = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/.config/instruct"
    );
    $files{'.config/instruct'} = $instruct_file;
    my $config_sh = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/config.sh"
    );
    $files{'config.sh'} = $config_sh;
    my $config_h  = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/config.h"
    );
    $files{'config.h'} = $config_h;
    my $pod_makefile = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/pod/Makefile"
    );
    $files{'pod/Makefile'} = $pod_makefile;
    my $makefile = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/Makefile"
    );
    $files{'Makefile'} = $makefile;
    my $myconfig = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/myconfig"
    );
    $files{'myconfig'} = $myconfig;
    my $policy_file = process_build_config(
      $perl_version,
      "$parent_dir/runtime_config/$os_family/$os_release/Policy.sh"
    );
    $files{'Policy.sh'} = $policy_file;

    # inject the other files that are needed
    $files{'cflags'} = "$parent_dir/runtime_config/$os_family/$os_release/cflags";
    $files{'makedepend'} = "$parent_dir/runtime_config/$os_family/$os_release/makedepend";
    $files{'runtests'} = "$parent_dir/runtime_config/$os_family/$os_release/runtests";

    chdir($temp_dir);
    download("Downloading 'perl-$perl_version.tar.gz'", 
      "http://www.cpan.org/src/5.0/perl-$perl_version.tar.gz");
    download("Downloading 'perl-$perl_version.tar.gz.md5.txt'",
      "http://www.cpan.org/src/5.0/perl-$perl_version.tar.gz.md5.txt");

    # checksum it
    chksum_file("perl-$perl_version.tar.gz", "perl-$perl_version.tar.gz.md5.txt");

    # unpack it
    unpack_tar_gz("perl-$perl_version.tar.gz");

    # copy config into directory tree
    say Dumper %files;
    say color('bold cyan') . "Entering directory '$temp_dir/perl-$perl_version'";
    chdir "$temp_dir/perl-$perl_version";
    foreach my $file (keys %files) {
        print color('bold cyan') . "Copying $files{$file} to $file: ";
        copy($files{$file}, "$temp_dir/perl-$perl_version/$file");
        say color('bold green'). 'OK'. color('reset');
    }

    chdir("./perl-$perl_version");
    # set our config,sh values
    my $current_dir = cwd;
    my $LD_LIBRARY_PATH = $ENV{'LD_LIBRARY_PATH'};
    $ENV{'LD_LIBRARY_PATH'} = "$current_dir:$LD_LIBRARY_PATH";
    $ENV{'BUILD_ZLIB'} = 'false';
    $ENV{'BUILD_BZIP2'} = 0;
    say color('bold white') . "Processing Configuration..." . color('reset');
    system("./Configure -S");
    say color('bold white') . "Running 'make depend'..." . color('reset');
    system("make", "depend");
    say color('bold white') . "Running 'make'" . color('reset');
    system("make");
    exit;
    say color('bold white') . "Running 'make test'" . color('reset');
    system("make", "test");
}

my sub install_deps ($distribution) {
    say color('bold cyan') . "INSTALLING DEPENDENCIES. PLEASE WAIT..." .
      color('reset');
    my $pkglib = pkglib->new($distribution);
    $pkglib->install_pkg($distribution, 'base', 'devel');
    $pkglib->install_pkg($distribution, 'c_cpp', 'devel');
}

sub main {
    umask 0022;
    if ($perl_version eq '') {
        if (defined $ENV{'PERL_VERSION'}) {
            my $perl_version = $ENV{'PERL_VERSION'};
        } else {
            say STDERR color('bold white on_red') .
              "No version defined to build! Exiting" .
              color('reset');
            exit -1;
        }
    }
    if (! defined($email_address)) {
        $email_address = 'builds@tolharadys.net';
    }
    $ENV{'PATH'} = "/bin:/usr/bin:/opt/Perl/bin";

    print color("bold white");
    say "OS PLATFORM: $platform";
    say "OS FAMILY: $distribution";
    print color('reset');

    my $temp_dir = tempdir(
        TMPDIR  => 1,
        CLEANUP => 0
    );

    # install deps
    install_deps($distribution);

    # get our runtime directory
    my $parent_dir = "$FindBin::Bin";
    print color("bold white");
    say "PARENT DIRECTORY: $parent_dir";
    say "TEMPORARY BUILD DIRECTORY: $temp_dir";
    print color('reset');

    # first build perl
    build_perl($perl_version, $parent_dir, $distribution, $os_release,
               $temp_dir);
}

GetOptions(
    'p|perl-version=s'  => \$perl_version,
    'e|email=s'         => \$email_address
);

main();