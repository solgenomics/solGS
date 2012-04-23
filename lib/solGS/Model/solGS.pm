package solGS::Model::solGS;
use Moose;
use namespace::autoclean;
use Bio::Chado::Schema;

extends 'Catalyst::Model';

=head1 NAME

solGS::Model::solGS - Catalyst Model for solGS

=head1 DESCRIPTION

solGS Catalyst Model.

=head1 AUTHOR

Isaak Y Tecle, iyt2@cornell.edu

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use File::Path qw/ mkpath /;
use File::Spec::Functions;


sub solgs_phenotype_data {
    my ($self, $pop_id) = @_;
    return $self->get_file('phenotype', $pop_id);
}

sub solgs_genotype_data {
    my ($self, $pop_id) = @_;
   return $self->get_file('genotype', $pop_id);
}


sub get_file {
    my ($self, $c, $type, $pop_id) = @_; 
    my $solgs_path = $self->solgs_path($c);
    my $trait = 'abc'; # figure out how to determine trait data file...
    
    if ($type eq 'phenotype')
    {
        return  catfile($solgs_path, $pop_id, $type, $trait);
    }
    else
    {
    return  catfile($solgs_path, $pop_id, $type);
    }
}


sub file_paths {
    my ($self, $c, $pop_id) = @_; 
    my $solgs_path = catfile($self->solgs_path($c), $pop_id);
    my $geno_path  = catfile($solgs_path, 'genotype');
    my $pheno_path = catfile($solgs_path, 'phenotype');
  
    mkpath ([$geno_path, $pheno_path], 0, 0755);        
    return  $geno_path, $pheno_path;
   
}

sub solgs_path {
    my ($self, $c) = @_;
    return  $c->config->{'solgs'};
}


sub write_data {
#make query to db and store population level phenotype and genotype data in tab delimited files

}
sub data_quality {
#data quality, formatting check

}

sub search_trait {
    my ($self, $c, $trait) = @_;
    
    my $rs;
    if ($trait)
    {
        my $schema    = $c->dbic_schema("Bio::Chado::Schema");
        $rs = $schema->resultset("Cv::Cvterm")->search(
            { name  => { 'LIKE' => '%'.$trait .'%'},         
            },
            {
              columns => [ qw/ cvterm_id name definition / ] 
            },    
            { 
              page     => $c->req->param('page') || 1,
              rows     => 10,
              order_by => 'name'
            }
            );       
    }
    return $rs;      
}

sub search_populations {
 #search for GS  populations phenotyped for a trait. 
}


__PACKAGE__->meta->make_immutable;

1;
