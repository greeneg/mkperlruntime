#!/usr/bin/env perl

use strict;
use warnings;
use English;
use utf8;

use feature qw(
    lexical_subs
    say
    signatures
    switch
);
no warnings 'experimental::lexical_subs';
no warnings 'experimental::signatures';
no warnings 'experimental::smartmatch';

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

my $perl_version = undef;
my $email_address = undef;

my $appname = basename $0;

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

my sub build_perl ($perl_version, $parent_dir, $os_family, $os_release, $platform,
                   $temp_dir) {
    chdir($temp_dir) ||
      die "Cannot enter directory '$temp_dir/perl-$perl_version: $!";
    download("Downloading 'perl-$perl_version.tar.gz'", 
      "http://www.cpan.org/src/5.0/perl-$perl_version.tar.gz");
    download("Downloading 'perl-$perl_version.tar.gz.md5.txt'",
      "http://www.cpan.org/src/5.0/perl-$perl_version.tar.gz.md5.txt");

    # checksum it
    chksum_file("perl-$perl_version.tar.gz", "perl-$perl_version.tar.gz.md5.txt");

    # unpack it
    unpack_tar_gz("perl-$perl_version.tar.gz");

    # copy config into directory tree
    say color('bold cyan') . "Entering directory '$temp_dir/perl-$perl_version'";
    chdir "$temp_dir/perl-$perl_version" ||
      die "Cannot enter directory '$temp_dir/perl-$perl_version: $!";

    # set our config,sh values
    my $current_dir = cwd;
    my $LD_LIBRARY_PATH = $ENV{'LD_LIBRARY_PATH'};
    if ($os_family eq 'linux') {
        $ENV{'LD_LIBRARY_PATH'} = "$current_dir:$LD_LIBRARY_PATH";
    }
    $ENV{'BUILD_ZLIB'} = 'false';
    $ENV{'BUILD_BZIP2'} = 0;
    say color('bold white') . "Processing Configuration..." . color('reset');
    my $cfg_command = "/bin/sh ./Configure -des ";
    my @cfg_flags;
    given ($platform) {
        when ('darwin') {
            @cfg_flags = (
                "-Dperladmin=$email_address",
                '-Dlocincpth=\'/opt/local/include /opt/local/include/db48 /usr/local/include\'',
                '-Dloclibpth=\'/opt/local/lib /opt/local/lib/db48 /usr/local/lib\'',
                '-Dhint=recommended',
                '-Duseposix=true',
                '-Duseithreads=define',
                '-Dusemultiplicity=define',
                '-Duse64bitint=define',
                '-Duse64bitall=define',
                '-Duselongdouble=define',
                '-Duseshrplib=true',
                '-Dlibperl=libperl.dylib',
                "-Dprefix=/opt/Perl-$perl_version",
                "-Dsiteprefix=/opt/Perl-$perl_version",
                "-Dinstallprefix=/opt/Perl-$perl_version",
                "-Dbin=/opt/Perl-$perl_version/bin",
                "-Dscriptdir=/opt/Perl-$perl_version/bin",
                "-Dprivlibdir=/opt/Perl-$perl_version/lib/perl5/$perl_version",
                "-Darchlibdir=/opt/Perl-$perl_version/lib/perl5/$perl_version/darwin-thread-multi-ld-2level",
                "-Dman1dir=/opt/Perl-$perl_version/share/man/man1",
                "-Dman3dir=/opt/Perl-$perl_version/share/man/man3",
                "-Dhtml1dir=/opt/Perl-$perl_version/share/doc/HTML",
                "-Dhtml3dir=/opt/Perl-$perl_version/share/doc/HTML",
                "-Dsitebin=/opt/Perl-$perl_version/bin",
                "-Dsitescript=/opt/Perl-$perl_version/bin",
                "-Dsitelib=/opt/Perl-$perl_version/lib/perl5/site_perl/$perl_version",
                "-Dsitearch=/opt/Perl-$perl_version/lib/perl5/site_perl/$perl_version/darwin-thread-multi-ld-2level",
                "-Dsiteman1dir=/opt/Perl-$perl_version/share/man/man1",
                "-Dsiteman3dir=/opt/Perl-$perl_version/share/man/man3",
                "-Dsitehtml1dir=/opt/Perl-$perl_version/share/doc/HTML",
                "-Dsitehtml3dir=/opt/Perl-$perl_version/share/doc/HTML"
            );
        }
    }
    print color('white');
    system("$cfg_command @cfg_flags");
    say color('bold white') . "Running 'make depend'..." . color('reset');
    print color('white');
    system("make", "depend");
    say color('bold white') . "Running 'make'" . color('reset');
    system("make");
    say color('bold white') . "Running 'make test'" . color('reset');
    system("make", "test");
}

my sub install_deps ($distribution) {
    say color('bold cyan') . "INSTALLING DEPENDENCIES. PLEASE WAIT..." .
      color('reset');
    my $pkglib = pkglib->new($distribution);
    $pkglib->install_pkgs($distribution, 'base', 'core');
}

sub main {
    umask 0022;
    if (! defined $perl_version) {
        if (defined $ENV{'PERL_VERSION'}) {
            $perl_version = $ENV{'PERL_VERSION'};
        } else {
            $perl_version = '5.30.1';
        }
    }
    if (! defined($email_address)) {
        $email_address = 'builds@tolharadys.net';
    }
    $ENV{'PATH'} = "/bin:/usr/bin:/opt/Perl/bin";

    print color("bold white");
    say "OS PLATFORM: $platform";
    say "OS FAMILY: $distribution";

    say "TEMPDIR POLICY:";
    my $temp_dir = tempdir(
        TMPDIR  => 1,
        CLEANUP => 0
    );
    say " - USE GLOBAL TEMP";
    say " - CLEANUP";
    print color('reset');

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
               $platform, $temp_dir);
    chdir('/var/empty');
    say "OLD TEMP DIR: $temp_dir";
}

my sub help {
    say "$appname - Create Perl Runtimes";
    say "-" x 79 . "\n";
    say "OPTIONS:";
    say " -h|--help                           Print this message";
    say " -p|--perl-version=VERSION_STRING    Specify version to build. If";
    say "                                     not specified, will build version";
    say "                                     5.30.1";
    say " -e|--email=PERL_ADMIN_EMAIL         Email address for the person whom";
    say "                                     did this build run";
}

my sub version {
    say "$appname - Create Perl Runtimes";
    say "Version: 1.0";
    say "Copyright 2020, YggdrasilSoft, LLC.";
    say "Licensed under the Apache Public License, version 2";
}

GetOptions(
    'h|help'            => sub { help(); exit 0; },
    'v|version'         => sub { version(); exit 0; },
    'p|perl-version=s'  => \$perl_version,
    'e|email=s'         => \$email_address
) or help();

main();