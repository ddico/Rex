#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

package Rex::Resource::Common;

use strict;
use warnings;

# VERSION

require Exporter;
require Rex::Config;
use Rex::Resource;
use Data::Dumper;
use base qw(Exporter);
use vars qw(@EXPORT);

@EXPORT = qw(emit resource resource_name changed created removed);

sub changed { return "changed"; }
sub created { return "created"; }
sub removed { return "removed"; }

sub emit {
  my ( $type, $message ) = @_;
  if ( !$Rex::Resource::INSIDE_RES ) {
    die "emit() only allowed inside resource.";
  }

  Rex::Logger::debug( "Emiting change: " . $type . " - $message." );

  if ( $type eq changed ) {
    current_resource()->changed(1);
  }

  if ( $type eq created ) {
    current_resource()->created(1);
  }

  if ( $type eq removed ) {
    current_resource()->removed(1);
  }

  if ($message) {
    current_resource()->message($message);
  }
}

=over 4

=item resource($name, $function)

=cut

sub resource {
  my ( $name, $options, $function ) = @_;
  my $name_save = $name;

  if ( ref $options eq "CODE" ) {
    $function = $options;
    $options  = {};
  }

  if ( $name_save !~ m/^[a-zA-Z_][a-zA-Z0-9_]+$/ ) {
    Rex::Logger::info(
      "Please use only the following characters for resource names:", "warn" );
    Rex::Logger::info( "  A-Z, a-z, 0-9 and _", "warn" );
    Rex::Logger::info( "Also the resource should start with A-Z or a-z",
      "warn" );
    die "Wrong resource name syntax.";
  }

  my ( $class, $file, @tmp ) = caller;
  my $res = Rex::Resource->new(
    type         => "${class}::$name",
    name         => $name,
    display_name => ( $options->{name} || $name ),
    cb           => $function
  );

  my $func = sub {
    $res->call(@_);
  };

  if (!$class->can($name)
    && $name_save =~ m/^[a-zA-Z_][a-zA-Z0-9_]+$/ )
  {
    no strict 'refs';
    Rex::Logger::debug("Registering resource: ${class}::$name_save");

    my $code = $_[-2];
    *{"${class}::$name_save"} = $func;
    use strict;
  }
  elsif ( ( $class ne "main" && $class ne "Rex::CLI" )
    && !$class->can($name_save)
    && $name_save =~ m/^[a-zA-Z_][a-zA-Z0-9_]+$/ )
  {
    # if not in main namespace, register the task as a sub
    no strict 'refs';
    Rex::Logger::debug(
      "Registering resource (not main namespace): ${class}::$name_save");
    my $code = $_[-2];
    *{"${class}::$name_save"} = $func;

    use strict;
  }

  if ( exists $options->{export} && $options->{export} ) {

    # register in caller namespace
    no strict 'refs';
    my ($caller_pkg) = caller(1);
    if ( $caller_pkg eq "Rex" ) {
      ($caller_pkg) = caller(2);
    }
    Rex::Logger::debug("Registering $name_save in $caller_pkg namespace.");
    *{"${caller_pkg}::$name_save"} = $func;
    use strict;
  }
}

sub resource_name {
  Rex::Config->set( resource_name => current_resource()->{res_name} );
  return current_resource()->{res_name};
}

sub resource_ensure {
  my ($option) = @_;
  $option->{ current_resource()->{res_ensure} }->();
}

sub current_resource {
  return $Rex::Resource::CURRENT_RES[-1];
}

=back

=cut

1;
