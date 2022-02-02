package WebComponent::ModelMap;

use strict;
use warnings;

use base qw( WebComponent );

1;

use File::Temp;
use URI::Escape;

use FIG_Config;
use WebComponent::WebGD;
use Time::HiRes qw( gettimeofday  tv_interval);
use WebColors;

=pod

=head1 NAME

ModelMap - Visualization of the reactions in a model

=head1 DESCRIPTION

WebComponent that produces a KEGGMap colored by the reactions in
a list of models

=head1 METHODS

=over 4

=item * B<new> ()

Called when the object is initialized. Expands SUPER::new.

=cut

sub new {
    my $self = shift->SUPER::new(@_);
    $self->application->register_component( 'AjaxKeggMap', 'myAjaxKeggMap'.$self->id );
	$self->{parent_map} = $self->application()->component('myAjaxKeggMap'.$self->id);
	$self->{ajaxComponent} = undef;
	$self->{'ajaxFunction'} = { fn => 'build_map', target => 'modelmap_target', 
                                Cgi => '',
                                loading_text => 'Loading KEGG pathway...',
                                post_hook => 'post_hook',
                                componentId => '' };
	$self->{popups} = ''; 
	$self->{ajax} = undef;
	$self->{elapsed} = [gettimeofday()];
    return $self;
}

=item * B<output> ()
Returns the html output of the ModelMap component.
=cut

sub output {
    my ($self) = @_;
    unless(defined($self->{ajax})) {
        warn "Must provide an ajax component to AjaxKeggMap";
        return '';
    }
    my $html = "<div id='".$self->{'ajaxFunction'}->{target}."'>";
    $html .= $self->build_map();
    $html .= "</div>";
    return $html;
}

sub build_map {
	my ($self) = @_;
	#$self->{elapsed} = $self->elapsed_time($self->{elapsed}, ' seconds since start of ModelMap.');
	$self->setup();
	#$self->{elapsed} = $self->elapsed_time($self->{elapsed}, ' seconds since setup of ModelMap.');
	return $self->{popups} . $self->base_map()->output();
}

sub setup {
    my ($self) = @_;
	$self->{'ajaxFunction'}->{'componentId'} = 'ModelMap|'.$self->{_id};
    # Get web objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');

    # Parse CGI params
    my $model_list = [];
    my $pnum;
    if( defined( $cgi->param('model') ) ) {
        my @models = split( /,/, $cgi->param('model') );
        $model_list = \@models;
    }
    # Set a default pathway
    if( defined( $cgi->param('pathway') ) ) {
        $pnum = $cgi->param('pathway');
    } else { $pnum = '00020'; }
	
	# Setup base AjaxKeggMap object
	$self->{'ajaxFunction'}->{'Cgi'} = 'model=' . join(',', @$model_list);
	$self->{parent_map}->{'ajaxFunction'} = $self->{'ajaxFunction'};
	$self->base_map()->map_id($pnum);
	$self->{parent_map}->setup();
	#$self->{elapsed} = $self->elapsed_time($self->{elapsed}, ' seconds in pre-setup and parent of ModelMap.');
	
    # Build mappings between KEGG and Argonne IDs
    my ($KeggToArg,$ArgToKegg);
    my $rxnKEGGHash = $self->rxnKEGGHash();
    foreach my $key (%{$rxnKEGGHash}) {
    	if ($key =~ m/R\d\d\d\d\d/) {
    		$KeggToArg->{$key} = $rxnKEGGHash->{$key};
    	} elsif ($key =~ m/rxn\d+/) {
    		$ArgToKegg->{$key} = $rxnKEGGHash->{$key};
    	}
    }
    # Define an array of colors for painting reactions/compounds
    my $colors = WebColors::get_palette( 'varied' );

    # Get the kegg map component we're about to modify
    my $base_map = $self->base_map();

    # Save identity for ajax calls
    my $component = "ModelMap|".$self->{_id};

    # Get the KEGG map
	$base_map->map_id($pnum);

    # Build a list of highlights and tooltips
    my @hlight = ();
    my $rlist = $base_map->reaction_coordinates();
    my $clist = $base_map->compound_coordinates();
    # Iterate through reactions and build a highlight argument hash
   foreach my $kid ( keys %{$rlist} ) {
        if( defined( @{$KeggToArg->{$kid}} ) ) {
            my $rid = $KeggToArg->{$kid}->[0];
            my $param_hash =  { 'id' => $kid };

            # Format the tooltip and pop-up
            my ($tooltip, $pop_up, $hl_colors, $border, $ecs) = $self->reactionDisplay( $model_list, $rid, $kid );
            $param_hash->{'tooltip'} = $tooltip;
            $param_hash->{'link'} = "javascript:popUp( \"$rid\" );";
            $param_hash->{'color'} = $hl_colors;
	    $param_hash->{'border'} = "black" if $border;
	    $param_hash->{'ec'} = $ecs if $ecs;

            push @hlight, $param_hash;
            $self->{popups} .= $pop_up;
        }
    }
	#$self->{elapsed} = $self->elapsed_time($self->{elapsed}, ' seconds spent on reactions. ');
    # build an argument hash for compounds
    my $cpdAlsHash = $self->cpdKEGGHash();
    my $cpdHash = $self->cpdHash();
    foreach my $keggCompoundId (keys %{$clist} ) {
        if( defined($cpdAlsHash->{$keggCompoundId}) ) {
            my $cpd = $cpdHash->{$cpdAlsHash->{$keggCompoundId}->[0]};
            next unless(defined($cpd));
            # Define a basic hash to modify based on the compound
            my $param_hash = {  'id' => $keggCompoundId };
            my ($tooltip, $pop_up, $hl_colors) = $self->compoundDisplay( $model_list, $keggCompoundId, $cpd->id() );
            $param_hash->{'tooltip'} = $tooltip;
            $param_hash->{'link'} = "javascript:popUp(\"" . $cpd->id() . "\");";
            $param_hash->{'color'} = $hl_colors;
			$self->{popups} .= $pop_up;
            push @hlight, $param_hash;
        }
    }
	#$self->{elapsed} = $self->elapsed_time($self->{elapsed}, ' seconds spent on compounds. ');
    $self->{parent_map}->highlights( \@hlight );
}

sub reactionDisplay {
    my ($self,$model_list, $rid, $kid ) = @_;
    # Get web objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');
    # Links to various pages
    my $seed_link = "?page=ReactionViewer&reaction=";
    my $kegg_link ="http://www.genome.jp/dbget-bin/www_bget?";
    my $cpd_link = "?page=CompoundViewer&compound=";
    my $peg_link = "http://seed-viewer.theseed.org/seedviewer.cgi?page=Annotation&feature=fig";
    # Housekeeping
    my $map_error_strings = {};
    my $colors = WebColors::get_palette( 'varied' );
    # open divs
    my $tooltip = "<div style=\"padding:5px;\"><small>";
    my $pop_up_html = "<div id=$rid style=\"padding:5px;display:none;\">";
    # Get the reaction table
    my $rxn = $self->rxnHash()->{$rid};
    # Start with a reaction name
    $pop_up_html .= "<b>Reaction ".$figmodel->web()->create_reaction_link($rid,"",join(",",@{$model_list}))."</b><br>";
    $tooltip .= "<b>Reaction $rid</b><br>";
    if (defined($rxn->name())) {
		$tooltip .= $rxn->name();
		$pop_up_html .= $rxn->name();
    }
    $tooltip .= "<br><br>";
    $pop_up_html .= "<br><br>";
    # Add a KEGG ID field
    $tooltip .= "<b>KEGG ID:</b><br> $kid <br><br>";
    $pop_up_html .= "<b>KEGG ID:</b><br> <a href=$kegg_link"."rn+$kid target=\"_blank\">$kid</a><br><br>";
    # Add the equation to both with links on the pop-up
    $tooltip .= "<b>Equation:</b><br>";
    $pop_up_html .= "<b>Equation:</b> <br>";
    # Split the equation and transform compound codes into compound names
    foreach( split /\s/, $rxn->equation() ){
        my $cpd = $self->cpdHash()->{$_};
        if ( $cpd ){
            my $cpd_name = $cpd->name();
            $tooltip .= $cpd_name;
            $cpd_name =~ s/\+$//;
            $pop_up_html .= $figmodel->web()->CpdLinks($cpd->name(),"NAME");
        }
        else{
            $tooltip .= " $_ ";
            $pop_up_html .=" $_ ";
        }
    }
    $pop_up_html .= "<br><br>";
    $tooltip .= "<br><br>";
    # Add EC numbers to the pop-up
    $pop_up_html .= "<b>Enzyme(s)</b><br>";
    if( defined( $rxn->enzyme())){
        $pop_up_html .= "<ul style=\"margin-left:-15px\">";
        my @enzymes = split(/\|/, $rxn->enzyme());
        foreach (@enzymes) {
            chomp $_;
            next if(length($_) < 1);
            $pop_up_html .= "<li><a href=$kegg_link"."ec:$_  target=\"_blank\">$_</a></li>";
        }
        $pop_up_html .= "</ul>";
    }
    else{
        $pop_up_html .= "<br>&nbsp;&nbsp;&nbsp;&nbsp;None<br><br>";
    }
    # Color each reaction and add reaction information to the
    # tooltips and popups
    my $rxn_color = [];
    my $border = 0;
    my @ec;
    # Add pegs for each model
    if( @$model_list ) {
		my $fig = $application->data_handle('FIG');
        my $pegs_string .= "<b>Associated genes:</b><br>";
        # Iterate through the models
        for(my $i=0; $i <  @$model_list; $i++ ){
            my $modeldata = $self->modeldata($model_list->[$i]);
            if (defined($modeldata->{error})) {
            	next;
            }
            my $model = $modeldata->{model};
            my $rxnmdlHash = $modeldata->{rxnmdl};
            my $classtbl = $modeldata->{rxnclass};
            # Checking that the model exists
            next unless(defined($model));
            #Getting class and data for reaction from model
            my $model_color = $colors->[$i];
            # If this reaction is in this model, do stuff
            if(defined($rxnmdlHash->{$rid})) {
                my $class = $figmodel->web()->reactionClassHtml({
					classtbl => $classtbl,
					data => $rid
				});
                my $org_id = $model->genome();
                $pegs_string .= "<br>&nbsp;&nbsp;".$model_list->[$i]."<br>";
                my $output = $self->reaction()->parseGeneExpression({expression => $rxnmdlHash->{$rid}->[0]->pegs()});
                if (defined($output) && defined($output->{genes}->[0])) {
                	$pegs_string .= "<ul style=\"margin-left:-15px;\">";
                	if (defined($class) && length($class) > 0) {
						$pegs_string .= "<li>".$class."</li>";
						$border = $class =~ /Essential/ || $class =~ /Active/ if @$model_list == 1;
                    }
                    my $gene = lc($output->{genes}->[0]);
                    if (@{$output->{genes}} == 1 && ($gene =~ m/spontaneous/ || $gene =~ m/unknown/ || $gene =~ m/biolog/ || $gene =~ m/autocompletion/ || $gene =~ m/gap/)) {
                    	 $model_color = [ 128,0,128 ];
                    } else {
                		for (my $k=0; $k < @{$output->{genes}}; $k++) {
							if ($output->{genes}->[$k] =~ m/peg\.\d+/) {
								my $object = {
									ID => ["fig|".$org_id.".".$output->{genes}->[$k]]
								};
								$pegs_string .= "<li>".$figmodel->web()->create_feature_link($object)."</li>";
							} else {
								$pegs_string .= "<li>".$output->{genes}->[$k]."</li>";
							}
                		}
                    }
					$pegs_string .= "</ul>"; 
                } else {
					# If there are no pegs associated, also color it purple: assume gapfilled
					$pegs_string .= "<br>&nbsp;&nbsp;&nbsp;&nbsp;Gene unknown<br>";
					$model_color = [128,0,128];
                }
            } else {
				$model_color = [255,255,255];
            }
            push @$rxn_color, $model_color;
        }
        $tooltip .= $pegs_string;
        $pop_up_html .= $pegs_string;
    } else {
        # Color reactions white if there are no models
        $rxn_color = [ [255,255,255] ];
    }
    $tooltip .= "</small></div>";
    $pop_up_html .= "</div>";
    return ( $tooltip, $pop_up_html, $rxn_color, $border, @ec );
}

sub compoundDisplay {
    my ($self,$model_list, $kegg_cpd, $cpd ) = @_;

    # Get web objects
    my $application = $self->application();
    my $cgi = $application->cgi();
    my $figmodel = $application->data_handle('FIGMODEL');

    # Useful links
    my $rxn_link = "?page=ReactionViewer&reaction=";
    my $cpd_link = "?page=CompoundViewer&compound=";
    my $kegg_link ="http://www.genome.jp/dbget-bin/www_bget?";
    my $peg_link = "http://seed-viewer.theseed.org/seedviewer.cgi?page=Annotation&feature=fig";

    # Start pop_up/tooltip
    my $tooltip = "<div style=\"padding:5px;\"><small>";
    my $pop_up_html = "<div id=\"$cpd\" style=\"padding:5px;display:none;\">";

    # Initialize an empty color list
    my $cpd_color = [ ];

    # Get a compound data object
    my $cpd_object = $self->cpdHash()->{$cpd};

    # Get picture
    my $pic_path = $figmodel->{"jpeg absolute directory"}->[0].$cpd_object->id().".jpeg";
    if( -e $pic_path ){
        $pic_path =~ s/$figmodel->{"jpeg absolute directory"}->[0]/$figmodel->{"jpeg web directory"}->[0]/;

        $pop_up_html .= "<img name=\"structure\" width=\"100%\" src=\"$pic_path\">";
        $tooltip .= "<img name=\"structure\" width=\"250px\" src=\"$pic_path\">";
    }

    $tooltip .= "<br><br><br>";
    $pop_up_html .= "<br><br><br>";


    # Add compound id:
    $tooltip .= "<b>Compound $cpd:</b><br>";
    $pop_up_html .= "<b>Compound ".$figmodel->web()->CpdLinks($cpd,"IDONLY").":</b><br>";


    # Add names
    my $nameHash = $self->cpdNAMEHash();
    if (defined($nameHash->{$cpd})) {
	    my $cpdNames = $nameHash->{$cpd};
	    foreach my $cpdAls (@$cpdNames) {
	            $tooltip .= $cpdAls ."<br>";
	            $pop_up_html .= $cpdAls ."<br>";
	    }
    }

    $tooltip .= "<br>";
    $pop_up_html .= "<br>";

    # Add formula
    if( defined( $cpd_object->formula() )) {
        $tooltip .= $cpd_object->formula() ."<br>";
        $pop_up_html .= $cpd_object->formula() ."<br>";
    }

    $tooltip .= "<br>";
    $pop_up_html .= "<br>";

    # Add kegg IDs
    my $keggHash = $self->cpdKEGGHash();
    if (defined($keggHash->{$cpd})) {
	    $tooltip .= "<b>KEGG ID:</b><br>";
	    $pop_up_html .= "<b>KEGG ID:</b><br>";
	    $tooltip .= "<ul style=\"margin-left:-20px;\">";
	    $pop_up_html .= "<ul style=\"margin-left:-20px;\">";
	    my $keggAlses = $keggHash->{$cpd};
	    foreach my $als (@$keggAlses) {
	        $pop_up_html .= "<li><a href=\"".$kegg_link."rn+".$als."\" target=\"_blank\">".$als."</a></li>";
	        $tooltip .= "<li>" . $als . "</li>";
	    }
	    $tooltip .= "</ul>";
	    $pop_up_html .= "</ul>";
    }

    # Add charge
    $tooltip .= "<b>Charge: &nbsp;</b>";
    $pop_up_html .= "<b>Charge:&nbsp;</b>";

    if( defined( $cpd_object->charge() ) ){
        $tooltip .= $cpd_object->charge() ."<br>";
        $pop_up_html .= $cpd_object->charge() ."<br>";
    }

    $tooltip .= "<br>";
    $pop_up_html .= "<br>";

    # Add model specific information: transporters/biomass/coloring
    my %biomass;
    my %transport;
    my %transport_genes;
    my $transport_pegs_string;

    if( @$model_list ){
        # Get reaction table to get equations later
        # Iterate through models to get data we need
        for( my $i=0; $i < @$model_list ; $i++ ){
            my $mdldata = $self->modeldata($model_list->[$i]);
            if (defined($mdldata->{error})) {
            	next;
            }
            my $model = $mdldata->{model};
            my $model_cpds = $mdldata->{cpdtbl};
            my $rxnHash = $mdldata->{rxnmdl};
            my $org_id = $mdldata->{genome};
            # Format the genes header so it looks good
            if( $transport_pegs_string ){
                $transport_pegs_string .= "<br><br>".$model_list->[$i] . "<br><br>";
            }
            else{
                $transport_pegs_string .= "<ul style=\"margin-left:-20px;\">";
                $transport_pegs_string .= $model_list->[$i]. "<br><br>";
            }
            # Avoid weird things. Throw a visible error here if desired.
            next unless( defined( $model_cpds) );

            # Save a list of biomass reactions in each model
            if( defined( my $row = $model_cpds->get_row_by_key( $cpd, "DATABASE" ) ) ){
                my $color_default = 1;
                if( defined( $row->{"BIOMASS"} ) ){
                    $color_default = 0;

                    foreach( @{$row->{"BIOMASS"}} ){
                        push @{$biomass{$_}}, $model_list->[$i];
                    }

                    push @$cpd_color, [0,255,0];
                }

                # Save a list of transport reactions and the genes assosciated with them
                # in each model
                if( defined( $row->{"TRANSPORTERS"} ) ){
                    $color_default = 0;
                    foreach my $rxn ( @{$row->{"TRANSPORTERS"}} ){
                        push @{$transport{$rxn}}, $model_list->[$i];
                        # Get data for each reactoin
                        if(defined($rxnHash->{$rxn})){
                        	$transport_pegs_string .= "<li><a href=\"$rxn_link$rxn\" target=\"_blank\">$rxn</a>: ";
                            my $output = $self->reaction()->parseGeneExpression({expression => $rxnHash->{$rxn}->[0]->pegs()});
                            if (defined($output) && defined($output->{genes})) {
                            	for (my $i=0; $i < @{$output->{genes}}; $i++) {
                            		if ($i > 0) {
                            			$transport_pegs_string .= ", ";
                            		}
                            		$transport_pegs_string .= "<a href=".$peg_link."|".$org_id.".".$output->{genes}->[$i]." target=\"_blank\">".$output->{genes}->[$i]."</a>";
                            	}
                            }
                        }
                    }
                    # Color the compound transported
                    push @$cpd_color, [255,0,0];
                }

                # check to see if we've colored the compound yet
                if( $color_default ){
                    push @$cpd_color, [0,0,255];
                }
            }
            else{
                # If the compound isn't in a model, black it out
                push @$cpd_color, [0,0,0];
            }
        }

        # Compile and spit out the list of the transport reactions
        if( keys( %transport ) ){
            $pop_up_html .= "<b>Transport Reactions:</b><br>";
            $pop_up_html .= "<ul style=\"margin-left:-20px;\">";
            $tooltip .= "<b>Transport Reactions:</b><br>";
            $tooltip .= "<ul style=\"margin-left:-20px;\">";
            foreach( keys( %transport) ){
               my $eqn = "title";
                if( defined($self->rxnHash()->{$_})) {
                	my $rxn = $self->rxnHash()->{$_};
                    if( $rxn->equation() ){
                        $eqn = $rxn->equation();
                    }
                }

                my $model_string = join( ", ", @{$transport{$_}} ) if defined( $transport{$_} );

                $tooltip .= "<li>$_: $model_string</li>";
                $pop_up_html .= "<li><a title=\"$eqn\" href=\"$rxn_link"."$_\" target=\"_blank\">$_</a>: $model_string</li>";

            }
			
            # Now that we have our transport reactions all set, add the genes associated with them
            $tooltip .= "</ul>";
            $pop_up_html .= "</ul>";

            $tooltip .= "<b>Genes involved in Transport Reactions:</b>";
            $pop_up_html .= "<b>Genes involved in Transport Reactions:</b>";

            $tooltip .= $transport_pegs_string . "</ul>";
            $pop_up_html .= $transport_pegs_string . "</ul>";
        }
        # Format and add biomass reactions
        if( keys( %biomass ) ){
            $pop_up_html .= "<b>Biomass Reactions:</b><br>";
            $pop_up_html .= "<ul style=\"margin-left:-20px;\">";
            $tooltip .= "<b>Biomass Reactions:</b><br>";
            $tooltip .= "<ul style=\"margin-left:-20px;\">";
            foreach( keys( %biomass ) ){
                my $eqn = "title";
                if( defined($self->rxnHash()->{$_})) {
                    my $rxn = $self->rxnHash()->{$_};
                    if( $rxn->equation() ){
                        $eqn = $rxn->equation();
                    }
                }

                my $model_string = join( ", ", @{$biomass{$_}} ) if defined( $biomass{$_} );

                $tooltip .= "<li>$_ : $model_string</li>";
                $pop_up_html .= "<li><a title=\"$eqn\" href=\"$rxn_link"."$_\" target=\"_blank\">$_</a>: $model_string</li>";
            }
        }
        $tooltip .= "</ul>";
        $pop_up_html .= "</ul>";

    } else {
    # If there are no models, make it black
        push @$cpd_color, [0,0,0];
    }

    $tooltip .= "</small></div>";
    $pop_up_html .= "</div>";
    return ( $tooltip, $pop_up_html, $cpd_color );
}

sub base_map {
	my ($self) = @_;
	return $self->{parent_map}->base_map();
}

sub ajax {
	my ($self, $ajax) = @_;
	if(defined($ajax)) { $self->{ajax} = $ajax }
	$self->{parent_map}->ajax($self->{ajax});
	return $self->{ajax};
}

sub require_javascript {
    return [ "$FIG_Config::cgi_url/Html/PopUp.js" ];
}

sub elapsed_time {
    my ($self, $prev, $msg) = @_;
    warn tv_interval($prev) . ' sec elapsed ('.$msg.').';
    return [gettimeofday()];
}

sub rxnHash {
    my ($self) = @_;
    if (!defined($self->{_rxnHash})) {
    	my $rxns = $self->figmodel()->database()->get_objects("reaction");
    	for (my $i=0; $i < @{$rxns}; $i++) {
    		$self->{_rxnHash}->{$rxns->[$i]->id()} = $rxns->[$i];
    	}
    }
    return $self->{_rxnHash};
}

sub cpdHash {
    my ($self) = @_;
    if (!defined($self->{_cpdHash})) {
    	my $cpds = $self->figmodel()->database()->get_objects("compound");
    	for (my $i=0; $i < @{$cpds}; $i++) {
    		$self->{_cpdHash}->{$cpds->[$i]->id()} = $cpds->[$i];
    	}
    }
    return $self->{_cpdHash};
}

sub cpdNAMEHash {
    my ($self) = @_;
    if (!defined($self->{_cpdNAMEHash})) {
    	my $objs = $self->figmodel()->database()->get_objects("cpdals",{ 'type' => 'name' });
    	for (my $i=0; $i < @{$objs}; $i++) {
    		push(@{$self->{_cpdNAMEHash}->{$objs->[$i]->COMPOUND()}},$objs->[$i]->alias());
    		push(@{$self->{_cpdNAMEHash}->{$objs->[$i]->alias()}},$objs->[$i]->COMPOUND());
    	}
    }
    return $self->{_cpdNAMEHash};
}

sub cpdKEGGHash {
    my ($self) = @_;
    if (!defined($self->{_cpdKEGGHash})) {
    	my $objs = $self->figmodel()->database()->get_objects("cpdals",{ 'type' => 'KEGG' });
    	for (my $i=0; $i < @{$objs}; $i++) {
    		push(@{$self->{_cpdKEGGHash}->{$objs->[$i]->COMPOUND()}},$objs->[$i]->alias());
    		push(@{$self->{_cpdKEGGHash}->{$objs->[$i]->alias()}},$objs->[$i]->COMPOUND());
    	}
    }
    return $self->{_cpdKEGGHash};
}

sub rxnNAMEHash {
    my ($self) = @_;
    if (!defined($self->{_rxnNAMEHash})) {
    	my $objs = $self->figmodel()->database()->get_objects("rxnals",{ 'type' => 'name' });
    	for (my $i=0; $i < @{$objs}; $i++) {
    		push(@{$self->{_rxnNAMEHash}->{$objs->[$i]->REACTION()}},$objs->[$i]->alias());
    		push(@{$self->{_rxnNAMEHash}->{$objs->[$i]->alias()}},$objs->[$i]->REACTION());
    	}
    }
    return $self->{_rxnNAMEHash};
}

sub rxnKEGGHash {
    my ($self) = @_;
    if (!defined($self->{_rxnKEGGHash})) {
    	my $objs = $self->figmodel()->database()->get_objects("rxnals",{ 'type' => 'KEGG' });
    	for (my $i=0; $i < @{$objs}; $i++) {
    		push(@{$self->{_rxnKEGGHash}->{$objs->[$i]->REACTION()}},$objs->[$i]->alias());
    		push(@{$self->{_rxnKEGGHash}->{$objs->[$i]->alias()}},$objs->[$i]->REACTION());
    	}
    }
    return $self->{_rxnKEGGHash};
}

sub figmodel {
    my ($self) = @_;
    if (!defined($self->{_figmodel})) {
    	$self->{_figmodel} = $self->application()->data_handle('FIGMODEL');
    }
    return $self->{_figmodel};
}

sub modeldata {
    my ($self,$id) = @_;
    if (!defined($self->{_modeldata}->{$id})) {
    	$self->{_modeldata}->{$id}->{model} = $self->figmodel()->get_model($id);
    	if (!defined($self->{_modeldata}->{$id}->{model})) {
    		$self->{_modeldata}->{$id} = {error => "Model ".$id." not found!"};
    	} else {
	    	$self->{_modeldata}->{$id}->{cpdtbl} = $self->{_modeldata}->{$id}->{model}->compound_table();
	    	$self->{_modeldata}->{$id}->{rxnmdl} = $self->{_modeldata}->{$id}->{model}->rxnmdlHash();
	    	$self->{_modeldata}->{$id}->{genome} = $self->{_modeldata}->{$id}->{model}->genome();
	    	$self->{_modeldata}->{$id}->{rxnclass} =  $self->{_modeldata}->{$id}->{model}->reaction_class_table();
	    	$self->{_modeldata}->{$id}->{cpdclass} =  $self->{_modeldata}->{$id}->{model}->compound_class_table();
    	}
    }
    return $self->{_modeldata}->{$id};
}

sub reaction {
	my ($self) = @_;
    if (!defined($self->{_reaction})) {
		$self->{_reaction} = $self->figmodel()->get_reaction();
    }
    return $self->{_reaction};
}