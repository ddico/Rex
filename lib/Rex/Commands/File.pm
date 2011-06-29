#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

=head1 NAME

Rex::Commands::File - Transparent File Manipulation

=head1 DESCRIPTION

With this module you can manipulate files.

=head1 SYNOPSIS

 task "read-passwd", "server01", sub {
    my $fh = file_read "/etc/passwd";
    for my $line = ($fh->read_all) {
       print $line;
    }
    $fh->close;
 };

 task "read-passwd2", "server01", sub {
    say cat "/etc/passwd";
 };
 
 
 task "write-passwd", "server01", sub {
    my $fh = file_write "/etc/passwd";
    $fh->write("root:*:0:0:root user:/root:/bin/sh\n");
    $fh->close;
 };
    
 delete_lines_matching "/var/log/auth.log", matching => "root";
 delete_lines_matching "/var/log/auth.log", matching => qr{Failed};
 delete_lines_matching "/var/log/auth.log", 
                        matching => "root", qr{Failed}, "nobody";

=head1 EXPORTED FUNCTIONS

=over 4

=cut

package Rex::Commands::File;

use strict;
use warnings;
use Fcntl;

require Exporter;
use Data::Dumper;
use Rex::FS::File;
use Rex::Commands::Fs;

use vars qw(@EXPORT);
use base qw(Exporter);

@EXPORT = qw(file_write file_close file_read file_append cat delete_lines_matching append_if_no_such_line);

use vars qw(%file_handles);

=item file_write($file_name)

This function opens a file for writing (it will truncate the file if it already exists). It returns a Rex::FS::File object on success.

On failure it will die.

 my $fh;
 eval {
    $fh = file_write("/etc/groups");
 };
 
 # catch an error
 if($@) {
    print "An error occured. $@.\n";
    exit;
 }
 
 # work with the filehandle
 $fh->write("...");
 $fh->close;

=cut

sub file_write {
   my ($file) = @_;
   my $fh;

   Rex::Logger::debug("Opening file: $file for writing.");

   if(my $ssh = Rex::is_ssh()) {
      $fh = $ssh->sftp->open($file, O_WRONLY | O_CREAT | O_TRUNC );
   } else {
      open($fh, ">", $file) or die($!);
   }

   unless($fh) {
      Rex::Logger::debug("Can't open $file for writing.");
      die("Can't open $file for writing.");
   }

   return Rex::FS::File->new(fh => $fh);
}

=item file_append($file_name)

=cut

sub file_append {
   my ($file) = @_;
   my $fh;

   Rex::Logger::debug("Opening file: $file for appending.");

   if(my $ssh = Rex::is_ssh()) {
      if(is_file($file)) {
         $fh = $ssh->sftp->open($file, O_WRONLY | O_APPEND );
         my %stat = stat "$file";
         $fh->seek($stat{size});
      } 
      else {
         $fh = $ssh->sftp->open($file, O_WRONLY | O_CREAT | O_TRUNC );
      }
   } else {
      open($fh, ">>", $file) or die($!);
   }

   unless($fh) {
      Rex::Logger::debug("Can't open $file for appending.");
      die("Can't open $file for appending.");
   }

   return Rex::FS::File->new(fh => $fh);
}

=item file_read($file_name)

This function opens a file for reading. It returns a Rex::FS::File object on success.

On failure it will die.

 my $fh;
 eval {
    $fh = read("/etc/groups");
 };
 
 # catch an error
 if($@) {
    print "An error occured. $@.\n";
    exit;
 }
 
 # work with the filehandle
 my $content = $fh->read_all;
 $fh->close;

=cut

sub file_read {
   my ($file) = @_;
   my $fh;

   Rex::Logger::debug("Opening file: $file for reading.");

   if(my $ssh = Rex::is_ssh()) {
      $fh = $ssh->sftp->open($file, O_RDONLY);
   } else {
      open($fh, "<", $file) or die($!);
   }

   unless($fh) {
      Rex::Logger::debug("Can't open $file for reading.");
      die("Can't open $file for reading.");
   }

   return Rex::FS::File->new(fh => $fh);
}

=item cat($file_name)

This function returns the complete content of $file_name as a string.

 print cat "/etc/passwd";

=cut

sub cat {
   my ($file) = @_;

   my $fh = file_read($file);
   my $content = $fh->read_all;
   $fh->close;

   return $content;
}

=item delete_lines_matching($file, $regexp)

Delete lines that match $regexp in $file.

 task "clean-logs", sub {
     delete_lines_matching "/var/log/auth.log" => "root";
 };

=cut
sub delete_lines_matching {
   my ($file, @m) = @_;

   if(! is_file($file)) {
      Rex::Logger::info("File: $file not found.");
      return;
   }

   if(! is_writable($file)) {
      Rex::Logger::info("File: $file not writable.");
      return;
   }

   my $nl = $/;
   my @content = split(/$nl/, cat ($file));

   my $fh = file_write $file;

   OUT:
   for my $line (@content) {
      IN:
      for my $match (@m) {
         if(! ref($match) eq "Regexp") {
            $match = qr{$match};
         }

         if($line =~ $match) {
            next OUT;
         }
      }

      $fh->write($line . $nl);
   }
   $fh->close;
}

=item append_if_no_such_line($file, $new_line, @regexp)

Append $new_line to $file if none in @regexp is found.

 task "add-group", sub {
    append_if_no_such_line "/etc/groups", "mygroup:*:100:myuser1,myuser2";
 };

=cut
sub append_if_no_such_line {
   my ($file, $new_line, @m) = @_;

   if(! is_file($file)) {
      Rex::Logger::info("File: $file not found.");
      return;
   }

   if(! is_writable($file)) {
      Rex::Logger::info("File: $file not writable.");
      return;
   }

   my $nl = $/;
   my @content = split(/$nl/, cat ($file));

   for my $line (@content) {
      for my $match (@m) {
         if(! ref($match) eq "Regexp") {
            $match = qr{$match};
         }

         if($line =~ $match) {
            return 0;
         }
      }
   }

   push @content, $new_line;
   my $fh = file_write $file;
   $fh->write(join($nl, @content));
   $fh->close;

}


=back


=cut

1;
