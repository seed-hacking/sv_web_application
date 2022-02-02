package WebPage::ShowSeqs;

use strict;
use warnings;
use URI::Escape;
use HTML;
use Data::Dumper;
use File::Temp qw/ :POSIX /;

use FIG;
use FIGV;
use UnvSubsys;
use Tracer;
#  This is part of RAST and not in all SEEDs. It is now changed to a require
#  in the code that calls it.
# use SeedExport;

use base qw( WebPage );

1;


##################################################
##                   OPTIONS                    ##
#                   ---------                    #
# Sequence='DNA Sequence'                        #
# Sequence='DNA Sequence with flanking'          #
# FLANKING=$number                               #
# firstpoint=$number                             #
# secondpoint=$number                            #
# Sequence='Protein Sequence'                    #
# Download=1  for direct download                #
##################################################

##################################################
# Method for registering components etc. for the #
# application                                    #
##################################################
sub init {
  my ( $self ) = @_;

  $self->application->register_component( 'Table', 'PegTable' );
  $self->application->register_component( 'Info', 'CommentInfo');
}

sub require_javascript {

  return [ "$FIG_Config::cgi_url/Html/showfunctionalroles.js" ];

}

##############################################
# Website content is returned by this method #
##############################################
sub output {
  my ( $self ) = @_;

  # needed objects #
  my $application = $self->application();
  Trace("Accessing FIG object.") if T(3);
  $self->{ 'fig' } = $application->data_handle( 'FIG' );
  my $fig          = $self->{ 'fig' };
  Trace("No FIG object returned.") if T(3) && ! defined ($self->{'fig'});
  $self->{ 'cgi' } = $application->cgi;
  my $cgi          = $application->cgi;
  my $hiddenvalues = {};

  my $buttons = $self->get_spreadsheet_buttons();

  my $fastaseq = '';
  my $error = '';

  my @figids = $cgi->param( 'cds_checkbox' );
  unless ( scalar( @figids ) ) {
    @figids = $cgi->param('feature');
  }

   if ( $cgi->param('Align') )
   {
       # If alignment requested, redirect to page AlignSeqsClustal
       $cgi->param('fid', @figids);
       $cgi->param('align_format', 'clustal');

       if ( defined( $cgi->param('Sequence') ) )
       {
	   if ( $cgi->param('Sequence') eq 'Protein Sequence' ) 
	   {
	       $cgi->param('seq_format', 'protein');
	   }
	   elsif ( $cgi->param('Sequence') eq 'DNA Sequence' ) 
	   {
	       if ( defined( $cgi->param('firstpoint') ) || defined( $cgi->param('secondpoint') ) )
	       {
		   my($first, $second) = ($cgi->param('firstpoint'), $cgi->param('secondpoint'));

		   unless ($first  =~ /^-?\d+$/) { $first  = 0; }
		   unless ($second =~ /^-?\d+$/) { $second = 0; }
		   
		   if ( $first == 0 && $second == 0 )
		   {
		       # align DNA of genes only
		       $cgi->param('seq_format', 'DNA');
		   }
		   else
		   {
		       # align DNA of specified segment of DNA
		       $cgi->param('seq_format', 'pre');
		       ($first, $second) = sort {$b <=> $a} ($first, $second);
		       $cgi->param('firstpoint', $first);
		       $cgi->param('secondpoint', $second);
		   }
	       }
	       else
	       {
		   # align DNA of genes only
		   $cgi->param('seq_format', 'DNA');
	       }
	   }
       }

       # delete CGI parameters not requireed by AlignSeqsClustal
       $cgi->delete('Sequence', 'feature', 'Align');

       $application->redirect('AlignSeqsClustal');
       $application->do_redirect();
       die 'cgi_exit';
   }

  my $hiddenstring = '';

  my $wasin = 0;
  foreach my $key ( @figids ) {
    Trace("Processing $key.") if T(3);
    if ( $key =~ /cds_checkbox_(.*)/ ) {
      $key = $1;
    }

    $hiddenstring .= "<INPUT TYPE=HIDDEN ID='$key' NAME='feature' VALUE='$key'>";

    if ( $key =~/fig\|\d+.\d+.\w+.\d+/) {
      $wasin = 1;

      my $genome = $fig->genome_of( $key );
      my $rawseq;
      my $segment_text = '';

      if ( defined( $cgi->param( 'Sequence' ) ) && $cgi->param( 'Sequence' ) eq 'DNA Sequence with flanking' ) {
	my $feature_location = $fig->feature_location( $key );
	$rawseq = $self->get_flanking( $key );
      }
      elsif ( defined( $cgi->param( 'Sequence' ) ) && $cgi->param( 'Sequence' ) eq 'Protein Sequence' ) {
	$rawseq = $fig->get_translation( $key );
      }
      elsif ( defined( $cgi->param( 'Sequence' ) ) && $cgi->param( 'Sequence' ) eq 'DNA Sequence' &&
	      (defined( $cgi->param('firstpoint') ) || defined( $cgi->param('secondpoint') )) )
      {
	  my($first, $second) = ($cgi->param('firstpoint'), $cgi->param('secondpoint'));
	  
	  unless ($first  =~ /^-?\d+$/) { $first  = 0; }
	  unless ($second =~ /^-?\d+$/) { $second = 0; }
	  
	  if ( $first == 0 && $second == 0 ) {
	      # DNA sequence of entire gene
	      my $feature_location = $fig->feature_location( $key );
	      $rawseq = $fig->dna_seq( $genome, $feature_location );
	  } else {
	      # return DNA sequence of specified segment
	      $rawseq = $self->get_segment($key);
	      
	      ($first, $second) = sort {$b <=> $a} ($first, $second);
	      $segment_text = "[$first..$second upstream]";
	  }
      }
      else {
	my $feature_location = $fig->feature_location( $key );
	$rawseq = $fig->dna_seq( $genome, $feature_location );
      }

      my $function = $fig->function_of( $key );
      my $gs = $fig->genus_species( $genome );

      # remove any newlines, since we are putting them in here anyway
      $rawseq =~ s/\n//g;

      if ( !defined( $rawseq ) || $rawseq eq '' ) {
	$fastaseq = 'No sequence found<BR>';
      }
      else {
	my $seq = join( "\n", $rawseq =~ /.{1,60}/g );
	$fastaseq .= ">$key ";
	$fastaseq .= "$function "     if $function;
	$fastaseq .= "$segment_text " if $segment_text;
	$fastaseq .= "[$gs]\n$seq\n\n";
      }
    }
  }

  
  my $content = "<H1>Display fasta sequences</H1>\n";
  
  $content .= $self->start_form( 'showseqs' );
  $content .= $hiddenstring;
  $content .= $buttons;

  if ( $cgi->param( 'Download' ) ) {
    print "Content-Type:application/x-download\n"; 
    print "Content-Length: " . length( $fastaseq ) . "\n";
    print "Content-Disposition:attachment;filename=Sequences.fasta\n\n";
    print $fastaseq;
    die 'cgi_exit';
  }
  elsif ($self->{cgi}->param('DownloadGB'))
  {
      if ( eval { require SeedExport } )
      {
          my $temp = tmpnam();
          SeedExport::export_fids_as_GB($self->{fig}, \@figids, $temp);

          my $txt;
          my $fh;
          if (open($fh, "<", $temp))
          {
	      undef $/;
	      $txt = <$fh>;
	      close($fh);
          }

          # print STDERR "GB: $txt\n";
	  
          print "Content-Type:application/x-download\n"; 
          print "Content-Length: " . length( $txt ) . "\n";
          print "Content-Disposition:attachment;filename=Sequences.gb\n\n";
          print $txt;

          die 'cgi_exit';
      }
    else {
      $error .= "GenBank export not supported on this SEED<BR>\n";
    }
  }
  else {
    if ( $wasin ) {
      $content .= "<pre>";
      $content .= $fastaseq;
      $content .= "</pre>";
    }
    else {
      $error .= "No FIG Identifiers given to display<BR>\n";
    }
  }

  ###############################
  # Display errors and comments #
  ###############################
 
  if ( defined( $error ) && $error ne '' ) {
    $self->application->add_message( 'warning', $error );
  }

  $content .= $self->end_form();
  return $content;
}


sub return_genbank
{
    my($self) = @_;
}

sub get_spreadsheet_buttons {

  my ( $self ) = @_;
  my $application = $self->application;

  my $buttons = '';

  my $flankingfield = "<INPUT TYPE=TEXT NAME=FLANKING SIZE=5 VALUE='".( $self->{ 'cgi' }->param( 'FLANKING' ) || '500' )."'>";
  my $checked_dnaseq = '';
  if ( $self->{ 'cgi' }->param( 'Sequence' ) eq 'DNA Sequence' ) {
    $checked_dnaseq = 'CHECKED';
  }
  my $checked_dnaflank = '';
  if ( $self->{ 'cgi' }->param( 'Sequence' ) eq 'DNA Sequence with flanking' ) {
    $checked_dnaflank = 'CHECKED';
  }
  my $checked_proteinseq = '';
  if ( $self->{ 'cgi' }->param( 'Sequence' ) eq 'Protein Sequence' ) {
    $checked_proteinseq = 'CHECKED';
  }
  my $dnaseqradio = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"DNA Sequence\" ID=\"DNASEQ\" $checked_dnaseq >";
  my $dnaflankradio = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"DNA Sequence with flanking\" ID=\"DNAFLANK\" $checked_dnaflank >";
  my $proteinradio = "<INPUT TYPE=\"RADIO\" NAME=\"Sequence\" VALUE=\"Protein Sequence\" ID=\"PROTEIN\" $checked_proteinseq >";

  my $downloadbutton  = "<INPUT TYPE=SUBMIT class='button' name='Download' value='Download Sequences'>";
  my $showfastabutton  = "<INPUT TYPE=SUBMIT class='button' name='ShowFasta' value='Show Fasta'>";

  $buttons .= "<TABLE><TR><TD>$dnaseqradio DNA Sequence:</TD><TD> $dnaflankradio DNA Sequence with flanking: $flankingfield bases</TD><TD>$proteinradio Protein Sequence</TD></TR></TABLE><BR>";
  $buttons .= "<TABLE><TR><TD>$downloadbutton</TD><TD>$showfastabutton</TD></TR></TABLE>";
  return $buttons;
}


sub get_flanking {
  my ( $self, $fid ) = @_;

  my $feature_location = $self->{ 'fig' }->feature_location( $fid );
  my $genome = $self->{ 'fig' }->genome_of( $fid );
  my $additional = $self->{ 'cgi' }->param( 'FLANKING' ) || 500;

  my @loc = split /,/, $feature_location;
  my ( $contig, $beg, $end ) = BasicLocation::Parse( $loc[0] );

  if ( defined( $contig ) and defined( $beg ) and defined( $end ) ) {
    my ( $n1, $npre );
    if ( $beg < $end ) {
      $n1 = $beg - $additional;
      $n1 = 1 if $n1 < 1;
      $npre = $beg - $n1;
    }
    else {
      $n1 = $beg + $additional;
      my $clen = $self->{ 'fig' }->contig_ln( $genome, $contig );
      $n1 = $clen if $n1 > $clen;
      $npre = $n1 - $beg;
    }
    $loc[0] = join( '_', $contig, $n1, $end );
    
    # Add to the end of the last segment:
    ( $contig, $beg, $end ) = BasicLocation::Parse($loc[-1]);
    my ( $n2, $npost );
    if ( $beg < $end ) {
      $n2 = $end + $additional;
      my $clen = $self->{ 'fig' }->contig_ln( $genome, $contig );
      $n2 = $clen if $n2 > $clen;
      $npost = $n2 - $end;
    } 
    else {
      $n2 = $end - $additional;
      $n2 = 1 if $n2 < 1;
      $npost = $end - $n2;
    }
    $loc[-1] = join( '_', $contig, $beg, $n2 );
    
    my $seq = $self->{ 'fig' }->dna_seq( $genome, join( ',', @loc ) );
    if ( $seq ) {
      my $len = length( $seq );         # Get length before adding newlines
      $seq =~ s/(.{60})/$1\n/g;         # Cleaver way to wrap the sequence
      my $p1 = $npre + int( $npre/60 ); # End of prefix, adjusted for newlines
      my $p2 = $len - $npost;           # End of data,
      $p2 += int( $p2/60 );             # adjusted for newlines
      my $diff = $p2 - $p1;             # Characters of data
      
      $seq = lc( substr( $seq, 0, $p1 ) ) . uc( substr( $seq, $p1, $diff ) ) . lc( substr( $seq, $p2 ) );
      
    return $seq;
    }
  }
}

sub get_segment {
  my($self, $fid) = @_;

  my $genome = $self->{'fig'}->genome_of($fid);

  my $first  = $self->{'cgi'}->param('firstpoint');
  my $second = $self->{'cgi'}->param('secondpoint');
  ($first, $second) = sort {$b <=> $a} ($first, $second);

  my $feature_location = $self->{'fig'}->feature_location($fid);
  my @loc = split(/,/, $feature_location);
  my($contig, $beg, $end) = BasicLocation::Parse($loc[0]);

  my $segment_seq = '';

  if ( defined($contig) and defined($beg) and defined($end) ) {
      my($start, $stop);
      my($loc_pre, $loc_post) = ('', '');
      my $clen = $self->{'fig'}->contig_ln($genome, $contig);
      if ( $beg < $end ) {
	  # gene on plus strand
	  # $first and $second are sorted, so $start and $stop are sorted too, i.e. $start <= $stop
	  $start = $beg - $first;
	  $stop  = $beg - $second;
	  
	  # don't go beyond contig bounds
	  $start = 1 if $start <= 1;
	  $stop  = $clen if $stop > $clen;
	  
	  if ( $start < $beg )
	  {
	      if ( $stop < $beg ) {
		  $loc_pre  = join('_', $contig, $start, $stop);
	      } else {
		  $loc_pre  = join('_', $contig, $start, ($beg-1));
		  $loc_post = join('_', $contig, $beg, $stop);
	      }
	  }
	  else
	  {
	      $loc_post = join('_', $contig, $start, $stop);
	  }
      }
      else
      {
	  # gene on minus strand
	  # $first and $second are sorted, so $start and $stop are sorted too, i.e. $start >= $stop
	  $start = $beg + $first;
	  $stop  = $beg + $second;

	  # don't go beyond contig bounds
	  $stop  = 1 if $stop <= 1;
	  $start = $clen if $start > $clen;
	  
	  if ( $start > $beg )
	  {
	      if ( $stop > $beg ) {
		  $loc_pre  = join('_', $contig, $start, $stop);
	      } else {
		  $loc_pre  = join('_', $contig, $start, ($beg+1));
		  $loc_post = join('_', $contig, $beg, $stop);
	      }
	  }
	  else
	  {
	      $loc_post = join('_', $contig, $start, $stop);
	  }
      }

      my $seq_pre  = $loc_pre?  $self->{'fig'}->dna_seq($genome, $loc_pre)  : '';
      my $seq_post = $loc_post? $self->{'fig'}->dna_seq($genome, $loc_post) : '';
      
      $segment_seq = lc($seq_pre) . uc($seq_post);
  }

  return $segment_seq;
}
