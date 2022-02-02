package WebComponent::ReactionTable;
use strict;
use warnings;
use base qw( WebComponent );

=pod
=head1 NAME
ModelSelect - a select box for models
=head1 DESCRIPTION
WebComponent for a model select box
=head1 METHODS
=over 4
=item * B<new> ()
Called when the object is initialized. Expands SUPER::new.
=cut
sub new {
	my $self = shift->SUPER::new(@_);
	$self->application->register_component('ObjectTable','ReactionObjectTable'.$self->id);
	return $self;
}

=item * B<output> ()
Returns the html output of the ModelSelect component.
=cut
sub output {
	my ($self,$Width,$idList) = @_;
	my $application = $self->application();
	my $cgi = $application->cgi();
	if (!defined($Width)) {
		$Width = 800;	
	}
	my $filtered = 0;
	my $objectList;
	my $rxnHash = $self->rxnHash();
	my $modelHash = $self->modelHash();
	#Filtering by the input list of reaction IDs
	if (defined($idList)) {
		$filtered = 1;
		if (ref($idList) ne "ARRAY") {
			my @array = split(/,/,$idList);
			push(@{$idList},@array);
		}
		for (my $i=0; $i < @{$idList}; $i++) {
			if (defined($rxnHash->{$idList->[$i]})) {
				push(@{$objectList},$rxnHash->{$idList->[$i]});
			}
		}
		$rxnHash = {};
		for (my $i=0; $i < @{$objectList}; $i++) {
			$objectList->[$i]->{_rtid} = $objectList->[$i]->id();
			$rxnHash->{$objectList->[$i]->id()} = $objectList->[$i];
		}
	} elsif (!defined($modelHash->{array})) {
		foreach my $rxn (keys(%{$rxnHash})) {
			$rxnHash->{$rxn}->{_rtid} = $rxn;
			push(@{$objectList},$rxnHash->{$rxn});
		}
	}
	#Filtering by the selected models
	my $finalRxnHash;
	my $genomeHash;
	if (defined($modelHash->{array})) {
		my $codeHash;
		foreach my $rxn (keys(%{$rxnHash})) {
			$codeHash->{$rxnHash->{$rxn}->code()} = {
				data => $rxnHash->{$rxn},
				id => $rxnHash->{$rxn}->id()
			};
		}
		for (my $i=0; $i < @{$modelHash->{array}}; $i++) {
			#print STDERR "Handling model ".$i.":".$modelHash->{array}->[$i];
			if (!defined($genomeHash->{$modelHash->{$modelHash->{array}->[$i]}->{model}->genome()})) {
				$genomeHash->{$modelHash->{$modelHash->{array}->[$i]}->{model}->genome()} = $modelHash->{$modelHash->{array}->[$i]}->{model}->provenanceFeatureTable();
			}
			my $mdlrxnhash;
			my $mdlrxns = [keys(%{$modelHash->{$modelHash->{array}->[$i]}->{rxnmdl}})];
			for (my $j=0; $j < @{$mdlrxns}; $j++) {
				my $mdlrxn = $modelHash->{$modelHash->{array}->[$i]}->{rxnmdl}->{$mdlrxns->[$j]}->[0];
				my $id = $mdlrxns->[$j];
				if (defined($rxnHash->{$id})) {
					$finalRxnHash->{$id}->{data} = $rxnHash->{$id};
					$finalRxnHash->{$id}->{models}->{$modelHash->{array}->[$i]} = $mdlrxn;
				} else {
					if ($id =~ m/bio\d\d\d\d\d/) {
						my $obj = $self->figmodel()->database()->get_object("bof",{id=>$id});
						if (defined($obj)) {
							$rxnHash->{$id} = $obj;
							$finalRxnHash->{$id}->{data} = $obj;
							$finalRxnHash->{$id}->{models}->{$modelHash->{array}->[$i]} = $mdlrxn;
						}
					} else {
						if (!defined($mdlrxnhash)) {
							#print STDERR "Loading model DB\n";
							my $rxns = $modelHash->{$modelHash->{array}->[$i]}->{model}->figmodel()->database()->get_objects("reaction");
							for (my $i=0; $i < @{$rxns}; $i++) {
					    		$mdlrxnhash->{$rxns->[$i]->id()} = $rxns->[$i];
					    	}
						}
						if (!defined($mdlrxnhash->{$id})) {
							#print STDERR "Could not find ".$id."\n";
							next;	
						}
						if ($id =~ m/rxn[89]\d\d\d\d/) {
							if (defined($codeHash->{$mdlrxnhash->{$id}->code()})) {
								#print STDERR "Joined ".$id."\n";
								$finalRxnHash->{$codeHash->{$mdlrxnhash->{$id}->code()}->{id}}->{data} = $codeHash->{$mdlrxnhash->{$id}->code()}->{data};
								$finalRxnHash->{$codeHash->{$mdlrxnhash->{$id}->code()}->{id}}->{models}->{$modelHash->{array}->[$i]} = $mdlrxn;
							} else {
								#print STDERR "Added ".$id."\n";
								$codeHash->{$mdlrxnhash->{$id}->code()} = {
									data => $mdlrxnhash->{$id},
									id => $id.".".$modelHash->{array}->[$i]
								};
								$finalRxnHash->{$id.".".$modelHash->{array}->[$i]}->{data} = $mdlrxnhash->{$id};
								$finalRxnHash->{$id.".".$modelHash->{array}->[$i]}->{models}->{$modelHash->{array}->[$i]} = $mdlrxn;
							}
						} else {
							$codeHash->{$mdlrxnhash->{$id}->code()} = {
								data => $mdlrxnhash->{$id},
								id => $id
							};
							$rxnHash->{$id} = $mdlrxnhash->{$id};
							$finalRxnHash->{$id}->{data} = $mdlrxnhash->{$id};
							$finalRxnHash->{$id}->{models}->{$modelHash->{array}->[$i]} = $mdlrxn;
						}	
					}
				}
			}	
		}
		$objectList = [];
		foreach my $rxn (keys(%{$finalRxnHash})) {
			$finalRxnHash->{$rxn}->{data}->{_rtid} = $rxn;
			push(@{$objectList},$finalRxnHash->{$rxn}->{data});
		}
	}
	#print STDERR "CREATING TABLE WITH ".@{$objectList}." ROWS!";
	#Creating and configuring the object table
	my $tbl = $application->component('ReactionObjectTable'.$self->id);
    $tbl->set_type("reaction");
	$tbl->set_objects($objectList);
    #Setting table columns
    my $columns = [
	    { call => 'HASH:_rtid', name => 'Reaction', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionID' ) || "" },
	    { call => 'FUNCTION:name', name => 'Name', filter => 1, sortable => 1, width => '150', operand => $cgi->param( 'filterReactionName' ) || "" },
	    { input => {cpdHash => $self->cpdHash(),dataHash => $finalRxnHash}, function => 'FIGMODELweb:display_reaction_equation', call => 'THIS', name => 'Equation', filter => 1, sortable => 1, width => '300', operand => $cgi->param( 'filterReactionEquation' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_roles', call => 'FUNCTION:id', name => 'Roles', filter => 1, sortable => 1, width => '150', operand => $cgi->param( 'filterReactionRoles' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_subsystems', call => 'FUNCTION:id', name => 'Subsystems', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterReactionSubsys' ) || "" },
	    { input => {type => "reaction"}, function => 'FIGMODELweb:display_keggmaps', call => 'FUNCTION:id', name => 'KEGG maps', filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterReactionKEGGmap' ) || "" },
	    { function => 'FIGMODELweb:display_reaction_enzymes', call => 'THIS', name => 'Enzyme', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionEnzyme' ) || "" },
	    { input => {-delimiter => ",", object => "rxnals", function => "REACTION", type => "KEGG"}, function => 'FIGMODELweb:display_alias', call => 'FUNCTION:id', name => 'KEGG RID', filter => 1, sortable => 1, width => '50', operand => $cgi->param( 'filterReactionKEGGID' ) || "" },
	];
	my $modelString = "";
	my $selectedOrganism = "none";
    if (defined($modelHash->{array})) {
	    if (@{$modelHash->{array}} == 1) {
	    	push(@{$columns},{
	    		function => 'FIGMODELweb:display_reaction_notes',
	    		input => {
	    			dataHash => $finalRxnHash,
	    			model => $modelHash->{array}->[0]
	    		},
	    		call => 'THIS',
	    		name => "Notes",
	    		filter => 1,
	    		sortable => 1,
	    		width => '100',
	    		operand => $cgi->param( 'filterNotes' ) || ""
	    	});
		}
	    $selectedOrganism = $modelHash->{$modelHash->{array}->[0]}->{model}->genome();
	    foreach my $model (@{$modelHash->{array}}) {
	    	if (length($modelString) > 0) {
	    		$modelString .= ",";	
	    	}
	    	$modelString .= $model;
	    	push(@{$columns},{
	    		input => {
	    			modelid => $model,
	    			dataHash => $finalRxnHash,
	    			rxnclasses => $modelHash->{$model}->{rxnclass},
	    			featuretbl => $genomeHash->{$modelHash->{$model}->{model}->genome()}
	    		},
	    		function => 'FIGMODELweb:reaction_model_column',
	    		call => 'THIS', 
	    		name => $model, 
	    		filter => 1, 
	    		sortable => 1, 
	    		width => '100', 
	    		operand => $cgi->param( 'filter'.$model ) || ""
	    	});
	    }
    }
    if (defined($cgi->param('fluxIds'))) {
		my @fluxes = split(/,/,$cgi->param('fluxIds'));
		for (my $i=0; $i < @fluxes; $i++) {
			push(@{$columns},{ input => {fluxid=>$fluxes[$i]}, function => 'FIGMODELweb:display_reaction_flux', call => 'FUNCTION:id', name => "Flux #".($i+1), filter => 1, sortable => 1, width => '100', operand => $cgi->param( 'filterNotes' ) || "" });	
		}
	} 
    #Specifying table settings
    $tbl->add_columns($columns);
    $tbl->set_table_parameters({
    	show_column_select => "1",
    	enable_upload => "1",
    	show_export_button => "1",
    	sort_column => "Reaction",
    	width => $Width,
    	show_bottom_browse => "1",
    	show_top_browse => "1",
    	show_select_items_per_page => "1",
    	items_per_page => "50",
    });
    my $html = "";
    if (defined($modelHash->{array})) {
    	$html .= '<input type="hidden" id="selected_models" value="'.$modelString.'">'."\n";	
    }
    $html .= '<input type="hidden" id="selected_organism" value="'.$selectedOrganism.'">'."\n";
    return $html.$tbl->output();
}

sub base_table {
  my ($self) = @_;
  return $self->application()->component('ReactionObjectTable'.$self->id)->base_table();
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

sub modelHash {
    my ($self) = @_;
	if (!defined($self->{_modelHash})) {  
   		if (defined($self->application()->cgi()->param('model'))) {
			my $modelList = [split(/,/,$self->application()->cgi()->param('model'))];
			for (my $i=0; $i < @{$modelList}; $i++) {
				my $data = $self->modeldata($modelList->[$i]);
				if (!defined($data->{error})) {
					$self->{_modelHash}->{$modelList->[$i]} = $data;
					push(@{$self->{_modelHash}->{array}},$modelList->[$i]);
				}
			}
		}
	}
	return $self->{_modelHash};
}

sub reaction {
	my ($self) = @_;
    if (!defined($self->{_reaction})) {
		$self->{_reaction} = $self->figmodel()->get_reaction();
    }
    return $self->{_reaction};
}

1;