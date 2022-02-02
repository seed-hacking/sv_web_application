package DataHandler::FIGMODEL;
# DataHandler::FIGMODEL - data handler to SEED database via FIGMODEL
# Primary author: Christopher Henry (chenry@mcs.anl.gov), MCS Division, Argonne National Laboratory
# Created: 4/13/2009
use strict;
use warnings;
use base qw( DataHandler );
use Tracer;

use lib '/vol/model-prod/Model-SEED-core/config/';
#use lib '/home/chenry/Model-SEED-core/config/';
use ModelSEEDbootstrap;
use ModelSEED::globals;
use ModelSEED::FIGMODEL;

=head1 FIGMODEL Data Handler
#TITLE FIGMODELpmDataHandler
=head2 Introduction
=head2 Public Methods
=head3 handle
	my $FIGMODELObject = $dh->handle($optional_id);
=cut
sub handle {
  my ($self, $optional_id) = @_;
  my $cgi = $self->application->cgi;
  Trace("Data handler called.") if T(3);
  if (!defined($self->{'FIGMODEL'})) {
 	my $user = $self->application()->session->user;
 	if (!defined($user)) {
 		$self->{'FIGMODEL'} = ModelSEED::FIGMODEL->new();
 	} else {
 		$self->{'FIGMODEL'} = ModelSEED::FIGMODEL->new({userObj => $user});
 	}
  	ModelSEED::globals::SETFIGMODEL($self->{'FIGMODEL'});
  	$self->{'FIGMODEL'}->web()->cgi($cgi);
  }
  return $self->{'FIGMODEL'};
}

1;