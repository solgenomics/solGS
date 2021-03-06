package solGS::Controller::Root;
use Moose;
use namespace::autoclean;

use String::CRC;
use URI::FromHash 'uri';
use File::Path qw / mkpath  /;
use File::Spec::Functions qw / catfile catdir/;
use File::Temp qw / tempfile tempdir /;
use File::Slurp qw /write_file read_file :edit prepend_file/;
use File::Copy;
use File::Basename;
use Cache::File;
use Try::Tiny;
use List::MoreUtils qw /uniq/;
use Scalar::Util qw /weaken reftype/;
use CatalystX::GlobalContext ();
use Statistics::Descriptive;
use Math::Round::Var;
use Algorithm::Combinatorics qw /combinations/;
#use CXGN::Login;
#use CXGN::People::Person;
use CXGN::Tools::Run;
use JSON;

BEGIN { extends 'Catalyst::Controller::HTML::FormFu' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#

__PACKAGE__->config(namespace => '');

=head1 NAME

solGS::Controller::Root - Root Controller for solGS

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut


sub index :Path :Args(0) {
    my ($self, $c) = @_;     
    $c->forward('search');
}


sub submit :Path('/solgs/submit/intro') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{template} =  $self->template('/submit/intro.mas');
}


sub details_form : Path('/solgs/form/population/details') Args(0) {
    my ($self, $c) = @_;

    $self->load_yaml_file($c, 'population/details.yml');
    my $form = $c->stash->{form}; 
   
    if ($form->submitted_and_valid ) 
    {
        $c->res->redirect('/solgs/form/population/phenotype');
    }
    else 
    {
        $c->stash(template => $self->template('/form/population/details.mas'),
                  form     => $form
            );
    }
}


sub phenotype_form : Path('/solgs/form/population/phenotype') Args(0) {
    my ($self, $c) = @_;
    
    $self->load_yaml_file($c, 'population/phenotype.yml');
    my $form = $c->stash->{form};

    if ($form->submitted_and_valid) 
    {
      $c->res->redirect('/solgs/form/population/genotype');
    }        
    else
    {
        $c->stash(template => $self->template('/form/population/phenotype.mas'),
                  form     => $form
            );
    }

}


sub genotype_form : Path('/solgs/form/population/genotype') Args(0) {
    my ($self, $c) = @_;

    $self->load_yaml_file($c, 'population/genotype.yml');
    my $form = $c->stash->{form};

    if ($form->submitted_and_valid) 
    {
      $c->res->redirect('/solgs/population/12');
    }        
    else
    {
        $c->stash(template => $self->template('/form/population/genotype.mas'),
                  form     => $form
            );
    }

}

sub search : Path('/solgs/search') Args() {
    my ($self, $c) = @_;

    $self->load_yaml_file($c, 'search/solgs.yml');
    my $form = $c->stash->{form};

    $self->gs_traits_index($c);
    my $gs_traits_index = $c->stash->{gs_traits_index};
    
    my $project_rs = $c->model('solGS')->all_projects($c);
    $self->projects_links($c, $project_rs);
    my $projects = $c->stash->{projects_pages};

    my $query;
    if ($form->submitted_and_valid) 
    {
        $query = $form->param_value('search.search_term');
        $c->res->redirect("/solgs/search/result/traits/$query");       
    }        
    else
    {
        $c->stash(template        => $self->template('/search/solgs.mas'),
                  form            => $form,
                  message         => $query,
                  gs_traits_index => $gs_traits_index,
                  result          => $projects,
                  pager           => $project_rs->pager,
                  page_links      => sub {uri ( query => {  page => shift } ) }
            );
    }

}


sub projects_links {
    my ($self, $c, $pr_rs) = @_;

    my $projects = $self->get_projects_details($c, $pr_rs);

    my @projects_pages;
    foreach my $pr_id (keys %$projects) 
    {
        my $pr_name     = $projects->{$pr_id}{project_name};
        my $pr_desc     = $projects->{$pr_id}{project_desc};
        my $pr_year     = $projects->{$pr_id}{project_year};
        my $pr_location = $projects->{$pr_id}{project_location};
               
        my $checkbox = qq |<form> <input type="checkbox" name="project" value="$pr_id" /> </form> |;
        push @projects_pages, [ $checkbox, qq|<a href="/solgs/population/$pr_id" onclick="solGS.waitPage()">$pr_name</a>|, 
                               $pr_desc, $pr_location, $pr_year
        ];
    }

    $c->stash->{projects_pages} = \@projects_pages;

}


sub show_search_result_pops : Path('/solgs/search/result/populations') Args(1) {
    my ($self, $c, $trait_id) = @_;
    
    my $combine = $c->req->param('combine');
    
    if ($combine) 
    {
       
        my $ids = $c->req->param("$trait_id");
        my @pop_ids = split(/,/, $ids);        
        if (!@pop_ids) {@pop_ids = $ids;}

        my $ret->{status} = 'failed';
        if (@pop_ids) 
        {
            $ret->{status} = 'success';
            $ret->{populations} = \@pop_ids;
        }
               
        $ret = to_json($ret);
        
        $c->res->content_type('application/json');
        $c->res->body($ret);

    }
    else 
    {
        my $projects_rs = $c->model('solGS')->search_populations($c, $trait_id);
        my $trait       = $c->model('solGS')->trait_name($c, $trait_id);
    
        $self->get_projects_details($c, $projects_rs);
        my $projects = $c->stash->{projects_details};
        
        my @projects_list;
   
        foreach my $pr_id (keys %$projects) 
        {
            my $pr_name     = $projects->{$pr_id}{project_name};
            my $pr_desc     = $projects->{$pr_id}{project_desc};
            my $pr_year     = $projects->{$pr_id}{project_year};
            my $pr_location = $projects->{$pr_id}{project_location};

            my $checkbox = qq |<form> <input type="checkbox" name="project" value="$pr_id" onclick="getPopIds()"/> </form> |;

            push @projects_list, [ $checkbox, qq|<a href="/solgs/trait/$trait_id/population/$pr_id" onclick="solGS.waitPage()">$pr_name</a>|, 
                               $pr_desc, $pr_location, $pr_year
            ];
        }

        my $form;
        if ($projects_rs)
        {
            $self->get_trait_name($c, $trait_id);
       
            $c->stash(template   => $self->template('/search/result/populations.mas'),
                      result     => \@projects_list,
                      form       => $form,
                      trait_id   => $trait_id,
                      query      => $trait,
                      pager      => $projects_rs->pager,
                      page_links => sub {uri ( query => { trait => $trait, page => shift } ) }
                );
        }
        else
        {
            $c->res->redirect('/solgs/search');     
        }
    }

}


sub get_projects_details {
    my ($self,$c, $pr_rs) = @_;
 
    my ($year, $location, $pr_id, $pr_name, $pr_desc);
    my %projects_details = ();

    while (my $pr = $pr_rs->next) 
    {
       
        $pr_id   = $pr->project_id;
        $pr_name = $pr->name;
        $pr_desc = $pr->description;
       
        my $pr_yr_rs = $c->model('solGS')->project_year($c, $pr_id);
        
        while (my $pr = $pr_yr_rs->next) 
        {
            $year = $pr->value;
        }

        my $pr_loc_rs = $c->model('solGS')->project_location($c, $pr_id);
    
        while (my $pr = $pr_loc_rs->next) 
        {
            $location = $pr->description;          
        } 

        $projects_details{$pr_id}  = { 
                  project_name     => $pr_name, 
                  project_desc     => $pr_desc, 
                  project_year     => $year, 
                  project_location => $location,
        };
    }
        
    $c->stash->{projects_details} = \%projects_details;

}


sub show_search_result_traits : Path('/solgs/search/result/traits') Args(1) {
    my ($self, $c, $query) = @_;
  
    my @rows;
    my $result = $c->model('solGS')->search_trait($c, $query);
   
    while (my $row = $result->next)
    {
        my $id   = $row->cvterm_id;
        my $name = $row->name;
        my $def  = $row->definition;
        #my $checkbox = qq |<form> <input type="checkbox" name="trait" value="$name" onclick="getPopIds()"/> </form> |;
        my $checkbox;
        push @rows, [ $checkbox, qq |<a href="/solgs/search/result/populations/$id">$name</a>|, $def];      
    }

    if (@rows)
    {
       $c->stash(template   => $self->template('/search/result/traits.mas'),
                 result     => \@rows,
                 query      => $query,
                 pager      => $result->pager,
                 page_links => sub {uri ( query => { trait => $query, page => shift } ) }
           );
    }
    else
    {
        $self->gs_traits_index($c);
        my $gs_traits_index = $c->stash->{gs_traits_index};
        
        my $project_rs = $c->model('solGS')->all_projects($c);
        $self->projects_links($c, $project_rs);
        my $projects = $c->stash->{projects_pages};
       
        $self->load_yaml_file($c, 'search/solgs.yml');
        my $form = $c->stash->{form};

        $c->stash(template        => $self->template('/search/solgs.mas'),
                  form            => $form,
                  message         => $query,
                  gs_traits_index => $gs_traits_index,
                  result          => $projects,
                  pager           => $project_rs->pager,
                  page_links      => sub {uri ( query => {  page => shift } ) }
            );
    }

} 


sub population : Regex('^solgs/population/([\d]+)(?:/([\w+]+))?'){
    my ($self, $c) = @_;
   
    my ($pop_id, $action) = @{$c->req->captures};

    if ($pop_id )
    {   
        $c->stash->{pop_id} = $pop_id;  
        $self->phenotype_file($c);
        $self->genotype_file($c);
        $self->get_all_traits($c);
        $self->project_description($c, $pop_id);

        $c->stash->{template} = $self->template('/population.mas');
      
        if ($action && $action =~ /selecttraits/ ) {
            $c->stash->{no_traits_selected} = 'none';
        }
        else {
            $c->stash->{no_traits_selected} = 'some';
        }

        $self->select_traits($c);
    }
    else 
    {
        $c->throw(public_message =>"Required population id is missing.", 
                  is_client_error => 1, 
            );
    }
} 


sub project_description {
    my ($self, $c, $pr_id) = @_;

    my $pr_rs = $c->model('solGS')->project_details($c, $pr_id);

    while (my $row = $pr_rs->next)
    {
        $c->stash(project_id   => $row->id,
                  project_name => $row->name,
                  project_desc => $row->description
            );
    }
    
    $self->genotype_file($c);
    my $geno_file  = $c->stash->{genotype_file};
    my @geno_lines = read_file($geno_file);
    my $markers_no = scalar(split ('\t', $geno_lines[0])) - 1;

    $self->trait_phenodata_file($c);
    my $trait_pheno_file  = $c->stash->{trait_phenodata_file};
    my @trait_pheno_lines = read_file($trait_pheno_file) if $trait_pheno_file;

    my $stocks_no = @trait_pheno_lines ? scalar(@trait_pheno_lines) - 1 : scalar(@geno_lines) - 1;

    $self->phenotype_file($c);
    my $pheno_file = $c->stash->{phenotype_file};
    my @phe_lines  = read_file($pheno_file);   
    my $traits     = $phe_lines[0];

    $self->filter_phenotype_header($c);
    my $filter_header = $c->stash->{filter_phenotype_header};
   
    $traits       =~ s/$filter_header//g;

    my @traits    =  split (/\t/, $traits);    
    my $traits_no = scalar(uniq(@traits));

    $c->stash(markers_no => $markers_no,
              traits_no  => $traits_no,
              stocks_no  => $stocks_no
        );
}


sub select_traits   {
    my ($self, $c) = @_;

    $self->load_yaml_file($c, 'population/traits.yml');
    $c->stash->{traits_form} = $c->stash->{form};
}


sub trait :Path('/solgs/trait') Args(3) {
    my ($self, $c, $trait_id, $key, $pop_id) = @_;
   
    if ($pop_id && $trait_id)
    {   
        $self->get_trait_name($c, $trait_id);
        $c->stash->{pop_id} = $pop_id;
        $self->project_description($c, $pop_id);
                            
        $self->get_rrblup_output($c);
        $self->gs_files($c);

        $self->trait_phenotype_stat($c);
        
        $self->download_prediction_urls($c);     
        my $download_prediction = $c->stash->{download_prediction};
     
        #get prediction populations list..     
        $self->list_of_prediction_pops($c, $pop_id, $download_prediction);
     
        $self->get_trait_name($c, $trait_id);
        $c->stash->{template} = $self->template("/population/trait.mas");
    }
    else 
    {
        $c->throw(public_message =>"Required population id or/and trait id are missing.", 
                  is_client_error => 1, 
            );
    }
   
}


sub gs_files {
    my ($self, $c) = @_;
    
    $self->output_files($c);
    #$self->input_files($c);
    $self->model_accuracy($c);
    $self->blups_file($c);
    $self->download_urls($c);
    $self->top_markers($c);

}


sub input_files {
    my ($self, $c) = @_;
    
    $self->genotype_file($c);
    $self->phenotype_file($c);
   
    # my $prediction_population_file = 'cap123geno_prediction.csv';
    my $pred_pop_id = $c->stash->{prediction_pop_id};
    my $prediction_population_file;

    if ($pred_pop_id) 
    {
        $self->prediction_population_file($c, $pred_pop_id);
        $prediction_population_file = $c->stash->{prediction_population_file};
    }

    my $pheno_file  = $c->stash->{phenotype_file};
    my $geno_file   = $c->stash->{genotype_file};
    my $traits_file = $c->stash->{selected_traits_file};
    my $trait_file  = $c->stash->{trait_file};
    my $pop_id      = $c->stash->{pop_id};
   
    my $input_files = join ("\t",
                            $pheno_file,
                            $geno_file,
                            $traits_file,
                            $trait_file,
                            $prediction_population_file
        );

    my $name = "input_files_${pop_id}"; 
    my $tempfile = $self->create_tempfile($c, $name); 
    write_file($tempfile, $input_files);
    $c->stash->{input_files} = $tempfile;
  
}


sub output_files {
    my ($self, $c) = @_;
    
    my $pop_id   = $c->stash->{pop_id};
    my $trait    = $c->stash->{trait_abbr}; 
    my $trait_id = $c->stash->{trait_id}; 
    
    $self->gebv_marker_file($c);  
    $self->gebv_kinship_file($c); 
    $self->validation_file($c);
    $self->trait_phenodata_file($c);

    my $prediction_id = $c->stash->{prediction_pop_id};
    my $identifier    = $pop_id . '_' . $prediction_id;
    my $pred_pop_gebvs_file;
    
    if ($prediction_id) 
    {
        $self->prediction_pop_gebvs_file($c, $identifier, $trait_id);
        $pred_pop_gebvs_file = $c->stash->{prediction_pop_gebvs_file};
    }

    my $file_list = join ("\t",
                          $c->stash->{gebv_kinship_file},
                          $c->stash->{gebv_marker_file},
                          $c->stash->{validation_file},
                          $c->stash->{trait_phenodata_file},
                          $c->stash->{selected_traits_gebv_file},
                          $pred_pop_gebvs_file
        );
                          
    my $name = "output_files_${trait}_$pop_id"; 
    my $tempfile = $self->create_tempfile($c, $name); 
    write_file($tempfile, $file_list);
    
    $c->stash->{output_files} = $tempfile;

}


sub gebv_marker_file {
    my ($self, $c) = @_;
   
    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};

    my $data_set_type = $c->stash->{data_set_type};
       
    my $cache_data;

    if ($data_set_type =~ /combined populations/)
    {
        my $combo_identifier = $c->stash->{combo_pops_id}; 

        $cache_data = {key       => 'gebv_marker_combined_pops_'.  $trait . '_' . $combo_identifier,
                       file      => 'gebv_marker_'. $trait . '_' . $combo_identifier . '_combined_pops',
                       stash_key => 'gebv_marker_file'
        };
    }
    else
    {
    
       $cache_data = {key       => 'gebv_marker_' . $pop_id . '_'.  $trait,
                      file      => 'gebv_marker_' . $trait . '_' . $pop_id,
                      stash_key => 'gebv_marker_file'
       };
    }

    $self->cache_file($c, $cache_data);

}


sub trait_phenodata_file {
    my ($self, $c) = @_;
   
    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
    
    my $data_set_type = $c->stash->{data_set_type};
    
    my $cache_data;

    if ($data_set_type =~ /combined populations/)
    {
        my $combo_identifier = $c->stash->{combo_pops_id}; 

        $cache_data = {key       => 'phenotype_trait_combined_pops_'.  $trait . "_". $combo_identifier,
                       file      => 'phenotype_trait_'. $trait . '_' . $combo_identifier. '_combined_pops',
                       stash_key => 'trait_phenodata_file'
        };
    }
    else 
    {
        $cache_data = {key       => 'phenotype_' . $pop_id . '_'.  $trait,
                       file      => 'phenotype_trait_' . $trait . '_' . $pop_id,
                       stash_key => 'trait_phenodata_file'
        };
    }

    $self->cache_file($c, $cache_data);
}


sub gebv_kinship_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
    my $data_set_type = $c->stash->{data_set_type};
        
    my $cache_data;

    if ($data_set_type =~ /combined populations/)
    {
        my $combo_identifier = $c->stash->{combo_pops_id};
        $cache_data = {key       => 'gebv_kinship_combined_pops_'.  $combo_identifier . "_" . $trait,
                       file      => 'gebv_kinship_'. $trait . '_'  . $combo_identifier. '_combined_pops',
                       stash_key => 'gebv_kinship_file'

        };
    }
    else 
    {
    
        $cache_data = {key       => 'gebv_kinship_' . $pop_id . '_'.  $trait,
                       file      => 'gebv_kinship_' . $trait . '_' . $pop_id,
                       stash_key => 'gebv_kinship_file'
        };
    }

    $self->cache_file($c, $cache_data);

}


sub blups_file {
    my ($self, $c) = @_;
    
    $c->stash->{blups} = $c->stash->{gebv_kinship_file};
    $self->top_blups($c);
}


sub download_blups :Path('/solgs/download/blups/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    my $trait_abbr = $c->stash->{trait_abbr};
   
    my $dir = $c->stash->{solgs_cache_dir};
    my $blup_exp = "gebv_kinship_${trait_abbr}_${pop_id}";
    my $blups_file = $self->grep_file($dir, $blup_exp);

    unless (!-e $blups_file || -s $blups_file == 0) 
    {
        my @blups =  map { [ split(/\t/) ] }  read_file($blups_file);
    
        $c->stash->{'csv'}={ data => \@blups };
        $c->forward("View::Download::CSV");
    } 

}


sub download_marker_effects :Path('/solgs/download/marker/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    my $trait_abbr = $c->stash->{trait_abbr};
  
    my $dir = $c->stash->{solgs_cache_dir};
    my $marker_exp = "gebv_marker_${trait_abbr}_${pop_id}";
    my $markers_file = $self->grep_file($dir, $marker_exp);

    print STDERR "\nmarkers file: $markers_file :\t $marker_exp\n";
    unless (!-e $markers_file || -s $markers_file == 0) 
    {
        my @effects =  map { [ split(/\t/) ] }  read_file($markers_file);
    
        $c->stash->{'csv'}={ data => \@effects };
        $c->forward("View::Download::CSV");
    } 

}


sub download_urls {
    my ($self, $c) = @_;
    my $data_set_type = $c->stash->{data_set_type};
    my $pop_id;
    
    if ($data_set_type =~ /combined populations/)
    {
        $pop_id         = $c->stash->{combo_pops_id};
    }
    else 
    {
        $pop_id         = $c->stash->{pop_id};  
    }
    
    my $trait_id       = $c->stash->{trait_id};
    my $ranked_genos_file = $c->stash->{genotypes_mean_gebv_file};
    if ($ranked_genos_file) 
    {
        ($ranked_genos_file) = fileparse($ranked_genos_file);
    }
    
    my $blups_url      = qq | <a href="/solgs/download/blups/pop/$pop_id/trait/$trait_id">Download all GEBVs</a> |;
    my $marker_url     = qq | <a href="/solgs/download/marker/pop/$pop_id/trait/$trait_id">Download all marker effects</a> |;
    my $validation_url = qq | <a href="/solgs/download/validation/pop/$pop_id/trait/$trait_id">Download model accuracy report</a> |;
    my $ranked_genotypes_url = qq | <a href="/solgs/download/ranked/genotypes/pop/$pop_id/$ranked_genos_file">Download all ranked genotypes</a> |;
   
    $c->stash(blups_download_url            => $blups_url,
              marker_effects_download_url   => $marker_url,
              validation_download_url       => $validation_url,
              ranked_genotypes_download_url => $ranked_genotypes_url,
        );
}


sub top_blups {
    my ($self, $c) = @_;
    
    my $blups_file = $c->stash->{blups};
    
    my $blups = $self->convert_to_arrayref($c, $blups_file);
  
    my @top_blups = @$blups[0..9];
 
    $c->stash->{top_blups} = \@top_blups;
}


sub top_markers {
    my ($self, $c) = @_;
    
    my $markers_file = $c->stash->{gebv_marker_file};

    my $markers = $self->convert_to_arrayref($c, $markers_file);
    
    my @top_markers = @$markers[0..9];

    $c->stash->{top_marker_effects} = \@top_markers;
}


sub validation_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
     
    my $data_set_type = $c->stash->{data_set_type};
       
    my $cache_data;

    if ($data_set_type =~ /combined populations/) 
    {
        my $combo_identifier = $c->stash->{combo_pops_id};
        $cache_data = {key       => 'cross_validation_combined_pops_'.  $trait . "_${combo_identifier}",
                       file      => 'cross_validation_'. $trait . '_' . $combo_identifier . '_combined_pops' ,
                       stash_key => 'validation_file'
        };
    }
    else
    {

        $cache_data = {key       => 'cross_validation_' . $pop_id . '_' . $trait, 
                       file      => 'cross_validation_' . $trait . '_' . $pop_id,
                       stash_key => 'validation_file'
        };
    }

    $self->cache_file($c, $cache_data);
}


sub combined_gebvs_file {
    my ($self, $c, $identifier) = @_;

    my $pop_id = $c->stash->{pop_id};
     
    my $cache_data = {key       => 'selected_traits_gebv_' . $pop_id . '_' . $identifier, 
                      file      => 'selected_traits_gebv_' . $pop_id . '_' . $identifier,
                      stash_key => 'selected_traits_gebv_file'
    };

    $self->cache_file($c, $cache_data);

}


sub download_validation :Path('/solgs/download/validation/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    my $trait_abbr = $c->stash->{trait_abbr};

    my $dir = $c->stash->{solgs_cache_dir};
    my $val_exp = "cross_validation_${trait_abbr}_${pop_id}";
    my $validation_file = $self->grep_file($dir, $val_exp);

    unless (!-e $validation_file || -s $validation_file == 0) 
    {
        my @validation =  map { [ split(/\t/) ] }  read_file($validation_file);
    
        $c->stash->{'csv'}={ data => \@validation };
        $c->forward("View::Download::CSV");
    }
 
}

 
sub prediction_population :Path('/solgs/model') Args(3) {
    my ($self, $c, $model_id, $pop, $prediction_pop_id) = @_;
 
    $c->res->redirect("/solgs/analyze/traits/population/$model_id/$prediction_pop_id");

}


sub prediction_pop_gebvs_file {    
    my ($self, $c, $identifier, $trait_id) = @_;

    my $cache_data = {key       => 'prediction_pop_gebvs_' . $identifier . '_' . $trait_id, 
                      file      => 'prediction_pop_gebvs_' . $identifier . '_' . $trait_id,
                      stash_key => 'prediction_pop_gebvs_file'
    };

    $self->cache_file($c, $cache_data);

}


sub download_prediction_GEBVs :Path('/solgs/download/prediction/model') Args(4) {
    my ($self, $c, $pop_id, $prediction, $prediction_id, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    $c->stash->{pop_id} = $pop_id;

    my $identifier = $pop_id . "_" . $prediction_id;
    $self->prediction_pop_gebvs_file($c, $identifier, $trait_id);
    my $prediction_gebvs_file = $c->stash->{prediction_pop_gebvs_file};
    
    unless (!-e $prediction_gebvs_file || -s $prediction_gebvs_file == 0) 
    {
        my @prediction_gebvs =  map { [ split(/\t/) ] }  read_file($prediction_gebvs_file);
    
        $c->stash->{'csv'}={ data => \@prediction_gebvs };
        $c->forward("View::Download::CSV");
    }
 
}


sub prediction_pop_analyzed_traits {
    my ($self, $c, $training_pop_id, $prediction_pop_id) = @_;
        
   # my $training_pop_id = $c->stash->{pop_id}; #134
   # my $prediction_pop_id = $c->stash->{prediction_pop_id}; #268
   # my $pred_pops_ids = $c->stash->{list_of_prediction_pops_ids};

    
    my $dir = $c->stash->{solgs_cache_dir};
    my @pred_files;

    opendir my $dh, $dir or die "can't open $dir: $!\n";
   
    my  @files  =  grep { /prediction_pop_gebvs_${training_pop_id}_${prediction_pop_id}/ && -f "$dir/$_" } 
                 readdir($dh); 
   
    closedir $dh; 

    my @copy_files = @files;
    my @trait_ids = map { s/prediction_pop_gebvs_|($training_pop_id)|($prediction_pop_id)|_//g ? $_ : 0} @copy_files;
  
    $c->stash->{prediction_pop_analyzed_traits} = \@trait_ids;
    $c->stash->{prediction_pop_analyzed_traits_files} = \@files;
    
}


sub download_prediction_urls {
    my ($self, $c, $training_pop_id, $prediction_pop_id) = @_;
  
    my $trait_ids;
    my $page_trait_id = $c->stash->{trait_id};
    my $page = $c->req->path;
         
    if($prediction_pop_id)
    {
        $self->prediction_pop_analyzed_traits($c, $training_pop_id, $prediction_pop_id);
        $trait_ids = $c->stash->{prediction_pop_analyzed_traits};
        
    } 
  
    my $trait_is_predicted = grep {/$page_trait_id/ } @$trait_ids;

    my $download_url;# = $c->stash->{download_prediction};

    if ($page =~ /solgs\/trait\//)
    {
        $trait_ids = [$page_trait_id];
    }

    foreach my $trait_id (@$trait_ids) 
    {
        $self->get_trait_name($c, $trait_id);
        my $trait_abbr = $c->stash->{trait_abbr};
        my $trait_name = $c->stash->{trait_name};

        
        $download_url   .= " | " if $download_url;        
        $download_url   .= qq | <a href="/solgs/download/prediction/model/$training_pop_id/prediction/$prediction_pop_id/$trait_id">$trait_abbr</a> | if $trait_id;
        $download_url = '' if (!$trait_is_predicted);
    }

    if ($download_url) 
    {    
        $c->stash->{download_prediction} = $download_url;
    }
    else
    {
        $c->stash->{download_prediction} = qq | <a href ="/solgs/model/$training_pop_id/prediction/$prediction_pop_id""  onclick="solGS.waitPage()">[ Predict Now ]</a> |;
    }
  
}
    


sub model_accuracy {
    my ($self, $c) = @_;
    my $file = $c->stash->{validation_file};
    my @report =();

    if ( !-e $file) { @report = (["Validation file doesn't exist.", "None"]);}
    if ( -s $file == 0) { @report = (["There is no cross-validation output report.", "None"]);}
    
    if (!@report) 
    {
        @report =  map  { [ split(/\t/, $_) ]}  read_file($file);
    }

    shift(@report); #add condition

    $c->stash->{accuracy_report} = \@report;
   
}


sub get_trait_name {
    my ($self, $c, $trait_id) = @_;

    my $trait_name = $c->model('solGS')->trait_name($c, $trait_id);
  
    if (!$trait_name) 
    { 
        $c->throw(public_message =>"No trait name corresponding to the id was found in the database.", 
                  is_client_error => 1, 
            );
    }

    my $abbr = $self->abbreviate_term($c, $trait_name);
   
    $c->stash->{trait_id}   = $trait_id;
    $c->stash->{trait_name} = $trait_name;
    $c->stash->{trait_abbr} = $abbr;

}

#creates and writes a list of GEBV files of 
#traits selected for ranking genotypes.
sub get_gebv_files_of_traits {
    my ($self, $c, $traits, $pred_pop_id) = @_;
    

    my $pop_id = $c->stash->{pop_id}; 
    my $dir = $c->stash->{solgs_cache_dir};
    my $gebv_files; 
    my $pred_gebv_files;

    if ($pred_pop_id) 
    {
        $self->prediction_pop_analyzed_traits($c, $pop_id, $pred_pop_id);
        $pred_gebv_files = $c->stash->{prediction_pop_analyzed_traits_files};
        
        foreach (@$pred_gebv_files)
        {
            $gebv_files .= catfile($dir, $_);
            $gebv_files .= "\t" unless (@$pred_gebv_files[-1] eq $_);
        }     
    } 

    unless ($pred_gebv_files->[0])
    {
        foreach my $tr (@$traits) 
        {    
            my $exp = "gebv_kinship_${tr}_${pop_id}"; 
            $gebv_files .= $self->grep_file($dir, $exp);
            $gebv_files .= "\t" unless (@$traits[-1] eq $tr);
        }
    }
    
    my $pred_file_suffix;
    $pred_file_suffix = '_' . $pred_pop_id  if $pred_pop_id; 
    
    my $name = "gebv_files_of_traits_${pop_id}${pred_file_suffix}";
    my $file = $self->create_tempfile($c, $name);
    write_file($file, $gebv_files);
   
    $c->stash->{gebv_files_of_traits} = $file;
    
}


sub gebv_rel_weights {
    my ($self, $c, $params, $pred_pop_id) = @_;
    
    my $pop_id      = $c->stash->{pop_id};
  
    my $rel_wts = "trait" . 'relative_weight' . "\n";
    foreach my $tr (keys %$params)
    {      
        my $wt = $params->{$tr};
        unless ($tr eq 'rank')
        {
            $rel_wts .= $tr . "\t" . $wt;
            $rel_wts .= "\n";#unless( (keys %$params)[-1] eq $tr);
        }
    }
  
    my $pred_file_suffix;
    $pred_file_suffix = '_' . $pred_pop_id  if $pred_pop_id; 
    
    my $name = "rel_weights_${pop_id}${pred_file_suffix}";
    my $file = $self->create_tempfile($c, $name);
    write_file($file, $rel_wts);
    
    $c->stash->{rel_weights_file} = $file;
    
}


sub ranked_genotypes_file {
    my ($self, $c, $pred_pop_id) = @_;

    my $pop_id = $c->stash->{pop_id};
 
    my $pred_file_suffix;
    $pred_file_suffix = '_' . $pred_pop_id  if $pred_pop_id;
  
    my $name = "ranked_genotypes_${pop_id}${pred_file_suffix}";
    my $file = $self->create_tempfile($c, $name);
    $c->stash->{ranked_genotypes_file} = $file;
   
}


sub mean_gebvs_file {
    my ($self, $c, $pred_pop_id) = @_;

    my $pop_id      = $c->stash->{pop_id};
   
    my $pred_file_suffix;
    $pred_file_suffix = '_' . $pred_pop_id  if $pred_pop_id;

    my $name = "genotypes_mean_gebv_${pop_id}${pred_file_suffix}";
    my $file = $self->create_tempfile($c, $name);
    $c->stash->{genotypes_mean_gebv_file} = $file;
   
}


sub download_ranked_genotypes :Path('/solgs/download/ranked/genotypes/pop') Args(2) {
    my ($self, $c, $pop_id, $genotypes_file) = @_;   
 
    $c->stash->{pop_id} = $pop_id;
  
    $genotypes_file = catfile($c->stash->{solgs_tempfiles_dir}, $genotypes_file);
  
    unless (!-e $genotypes_file || -s $genotypes_file == 0) 
    {
        my @ranks =  map { [ split(/\t/) ] }  read_file($genotypes_file);
    
        $c->stash->{'csv'}={ data => \@ranks };
        $c->forward("View::Download::CSV");
    } 

}


sub rank_genotypes : Private {
    my ($self, $c, $pred_pop_id) = @_;

    my $pop_id      = $c->stash->{pop_id};
    

    my $input_files = join("\t", 
                           $c->stash->{rel_weights_file},
                           $c->stash->{gebv_files_of_traits}
        );

    $self->ranked_genotypes_file($c, $pred_pop_id);
    $self->mean_gebvs_file($c, $pred_pop_id);

    my $output_files = join("\t",
                            $c->stash->{ranked_genotypes_file},
                            $c->stash->{genotypes_mean_gebv_file}
        );
 
   
    my $pred_file_suffix;
    $pred_file_suffix = '_' . $pred_pop_id  if $pred_pop_id;
    
    my $name = "output_rank_genotypes_${pop_id}${pred_file_suffix}";
    my $output_file = $self->create_tempfile($c, $name);
    write_file($output_file, $output_files);
    $c->stash->{output_files} = $output_file;
    
    $name = "input_rank_genotypes_${pop_id}${pred_file_suffix}";
    my $input_file = $self->create_tempfile($c, $name);
    write_file($input_file, $input_files);
    $c->stash->{input_files} = $input_file;

    $c->stash->{r_temp_file} = "rank-gebv-genotypes-${pop_id}${pred_file_suffix}";
    $c->stash->{r_script}    = 'R/rank_genotypes.r';
    
    $self->run_r_script($c);
    $self->download_urls($c);
    $self->top_ranked_genotypes($c);
  
}

#based on multiple traits performance
sub top_ranked_genotypes {
    my ($self, $c) = @_;
    
    my $genotypes_file = $c->stash->{genotypes_mean_gebv_file};
  
    my $genos_data = $self->convert_to_arrayref($c, $genotypes_file);
    my @top_genotypes = @$genos_data[0..9];
    
    $c->stash->{top_ranked_genotypes} = \@top_genotypes;
}


#converts a tab delimitted > two column data file
#into an array of array ref
sub convert_to_arrayref {
    my ($self, $c, $file) = @_;

    open my $fh, $file or die "couldnot open $file: $!";    
    
    my @data;   
    while (<$fh>)
    {
        push @data,  map { [ split(/\t/) ] } $_;
    }
   
    shift(@data);
    
    return \@data;

}


sub trait_phenotype_file {
    my ($self, $c, $pop_id, $trait) = @_;

    my $dir = $c->stash->{solgs_cache_dir};
    my $exp = "phenotype_trait_${trait}_${pop_id}";
    my $file = $self->grep_file($dir, $exp);
   
    $c->stash->{trait_phenotype_file} = $file;

}

#retrieve from db prediction pops relevant to the
#training population
sub list_of_prediction_pops {
    my ($self, $c, $training_pop_id, $download_prediction) = @_;

    $self->list_of_prediction_pops_file($c, $training_pop_id);
    my $pred_pops_file = $c->stash->{list_of_prediction_pops_file};

    my @pred_pops_ids = split(/\n/, read_file($pred_pops_file));
    my $pop_ids;

    if(!@pred_pops_ids)
    {
        my $pred_pops_ids2 = $c->model('solGS')->prediction_pops($c, $training_pop_id);
        @pred_pops_ids = @$pred_pops_ids2;

        foreach (@pred_pops_ids)
        {
            $pop_ids .= $_ ."\n";
        }
        write_file($pred_pops_file, $pop_ids);
    }

    my @pred_pops;

    foreach my $prediction_pop_id (@pred_pops_ids)

    {
        my $pred_pop_rs = $c->model('solGS')->project_details($c, $prediction_pop_id);
        my $pred_pop_link;

        while (my $row = $pred_pop_rs->next)
        {
            my $name = $row->name;
            my $desc = $row->description;

            $pred_pop_link = qq | <a href="/solgs/model/$training_pop_id/prediction/$prediction_pop_id" onclick="solGS.waitPage()">$name</a> |;

            my $pr_yr_rs = $c->model('solGS')->project_year($c, $prediction_pop_id);
            my $project_yr;

            while ( my $yr_r = $pr_yr_rs->next )
            {
                $project_yr = $yr_r->value;

            }

            $self->download_prediction_urls($c, $training_pop_id, $prediction_pop_id);
            my $download_prediction = $c->stash->{download_prediction};

            push @pred_pops,  ['', $pred_pop_link, $desc, 'F1', $project_yr, $download_prediction];
        }
    }

    $c->stash->{list_of_prediction_pops} = \@pred_pops;

}


sub list_of_prediction_pops_file {
    my ($self, $c, $training_pop_id)= @_;

    my $cache_data = {key       => 'list_of_prediction_pops' . $training_pop_id,
                      file      => 'list_of_prediction_pops_' . $training_pop_id,
                      stash_key => 'list_of_prediction_pops_file'
    };

    $self->cache_file($c, $cache_data);

}


sub prediction_population_file {
    my ($self, $c, $pred_pop_id) = @_;

    
    my $tmp_dir = $c->stash->{solgs_tempfiles_dir};

    my ($fh, $tempfile) = tempfile("prediction_population_${pred_pop_id}-XXXXX", 
                                   DIR => $tmp_dir
        );

    $c->stash->{prediction_pop_id} = $pred_pop_id;
    $self->genotype_file($c, $pred_pop_id);
    my $pred_pop_file = $c->stash->{pred_genotype_file};

    $fh->print($pred_pop_file);
    $fh->close; 

    $c->stash->{prediction_population_file} = $tempfile;
  
}


sub traits_to_analyze :Regex('^solgs/analyze/traits/population/([\d]+)(?:/([\d+]+))?') {
    my ($self, $c) = @_; 
   
    my ($pop_id, $prediction_id) = @{$c->req->captures};
    
    $c->stash->{pop_id} = $pop_id;
    $c->stash->{prediction_pop_id} = $prediction_id;
  
    my @selected_traits = $c->req->param('trait_id');
  
    my $single_trait_id;
    if (!@selected_traits)
    {
        $c->stash->{model_id} = $pop_id; 
        $self->analyzed_traits($c);
        @selected_traits = @{$c->stash->{analyzed_traits}};       
    }

    if (!@selected_traits)
    {
        $c->res->redirect("/solgs/population/$pop_id/selecttraits");
    }
    elsif (scalar(@selected_traits) == 1)
    {
        $single_trait_id = $selected_traits[0];
        if (!$prediction_id)
        {
            $c->res->redirect("/solgs/trait/$single_trait_id/population/$pop_id");
        } 
        else
        {
    
            my $name  = "trait_info_${single_trait_id}_pop_${pop_id}";
            my $file2 = $self->create_tempfile($c, $name);
       
            $c->stash->{trait_file} = $file2;
            $c->stash->{trait_abbr} = $selected_traits[0];
           
            my $acronym_pairs = $self->get_acronym_pairs($c);                   
            if ($acronym_pairs)
            {
                foreach my $r (@$acronym_pairs) 
                {
                    if ($r->[0] eq $selected_traits[0]) 
                    {
                        my $trait_name =  $r->[1];
                        $trait_name    =~ s/\n//g;                                
                        my $trait_id   =  $c->model('solGS')->get_trait_id($c, $trait_name);
                        $self->get_trait_name($c, $trait_id);
                    }
                }
            }
            
            $c->forward('get_rrblup_output');
        }
    }
    elsif(scalar(@selected_traits) > 1)
    {
        my ($traits, $trait_ids);    
        
        for (my $i = 0; $i <= $#selected_traits; $i++)
        {           
            if ($selected_traits[$i] =~ /\D/)
            {               
                my $acronym_pairs = $self->get_acronym_pairs($c);                   
                if ($acronym_pairs)
                {
                    foreach my $r (@$acronym_pairs) 
                    {
                        if ($r->[0] eq $selected_traits[$i]) 
                        {
                            my $trait_name =  $r->[1];
                            $trait_name    =~ s/\n//g;                                
                            my $trait_id   =  $c->model('solGS')->get_trait_id($c, $trait_name);

                            $traits    .= $r->[0];
                            $traits    .= "\t" unless ($i == $#selected_traits);
                            $trait_ids .= $trait_id;                                                        
                        }
                    }
                }
            }
            else 
            {
                my $tr = $c->model('solGS')->trait_name($c, $selected_traits[$i]);
   
                my $abbr = $self->abbreviate_term($c, $tr);
                $traits .= $abbr;
                $traits .= "\t" unless ($i == $#selected_traits); 

                    
                foreach (@selected_traits)
                {
                    $trait_ids .= $_; #$c->model('solGS')->get_trait_id($c, $_);
                }
            }                 
        } 

        my $identifier = crc($trait_ids);

        $self->combined_gebvs_file($c, $identifier);
        
        my $name = "selected_traits_pop_${pop_id}";
        my $file = $self->create_tempfile($c, $name);
        write_file($file, $traits);
        $c->stash->{selected_traits_file} = $file;

        $name = "trait_info_${single_trait_id}_pop_${pop_id}";
        my $file2 = $self->create_tempfile($c, $name);
       
        $c->stash->{trait_file} = $file2;
        $c->forward('get_rrblup_output');
  
    }
    # else
#     {
    
#     print STDERR "\ndo nothing for now..\n";
#     }
    $c->res->redirect("/solgs/traits/all/population/$pop_id/$prediction_id");

}


sub all_traits_output :Regex('^solgs/traits/all/population/([\d]+)(?:/([\d+]+))?') {
     my ($self, $c) = @_;
     
     my ($pop_id, $pred_pop_id) = @{$c->req->captures};

     my @traits = $c->req->param; 
     @traits = grep {$_ ne 'rank'} @traits;
     $c->stash->{pop_id} = $pop_id;

     if ($pred_pop_id)
     {
         $c->stash->{prediction_pop_id} = $pred_pop_id;
         $c->stash->{population_is} = 'prediction population';
         $self->prediction_population_file($c, $pred_pop_id);
         
         my $pr_rs = $c->model('solGS')->project_details($c, $pred_pop_id);
         
         while (my $row = $pr_rs->next) 
         {
             $c->stash->{prediction_pop_name} = $row->name;
         }
     }
     else
     {
         $c->stash->{prediction_pop_id} = 'N/A';
         $c->stash->{population_is} = 'training population';
     }

     $c->stash->{model_id} = $pop_id; 
     $self->analyzed_traits($c);
     my @analyzed_traits = @{$c->stash->{analyzed_traits}};
 
     print STDERR "all_traits_out prediction pop: $analyzed_traits[0]\n";

     if (!@analyzed_traits) 
     {
         $c->res->redirect("/solgs/population/$pop_id/selecttraits/");
     }
   
     my @trait_pages;
     foreach my $tr (@analyzed_traits)
     {
         my $acronym_pairs = $self->get_acronym_pairs($c);
         my $trait_name;
         if ($acronym_pairs)
         {
             foreach my $r (@$acronym_pairs) 
             {
                 if ($r->[0] eq $tr) 
                 {
                     $trait_name = $r->[1];
                     $trait_name =~ s/\n//g;
                     $c->stash->{trait_name} = $trait_name;
                     $c->stash->{trait_abbr} = $r->[0];
                 }
             }

         }

         my $trait_id   = $c->model('solGS')->get_trait_id($c, $trait_name);
         my $trait_abbr = $c->stash->{trait_abbr}; 
        
         my $dir = $c->stash->{solgs_cache_dir};
         opendir my $dh, $dir or die "can't open $dir: $!\n";
    
         my @validation_file  = grep { /cross_validation_${trait_abbr}_${pop_id}/ && -f "$dir/$_" } 
                                readdir($dh);   
         closedir $dh; 
        
         my @accuracy_value = grep {/Average/} read_file(catfile($dir, $validation_file[0]));
         @accuracy_value    = split(/\t/,  $accuracy_value[0]);

         push @trait_pages,  [ qq | <a href="/solgs/trait/$trait_id/population/$pop_id" onclick="solGS.waitPage()">$trait_abbr</a>|, $accuracy_value[1] ];
     }


     $self->project_description($c, $pop_id);
     my $project_name = $c->stash->{project_name};
     my $project_desc = $c->stash->{project_desc};
     
     my @model_desc = ([qq | <a href="/solgs/population/$pop_id">$project_name</a> |, $project_desc, \@trait_pages]);
     
     $c->stash->{template}    = $self->template('/population/multiple_traits_output.mas');
     $c->stash->{trait_pages} = \@trait_pages;
     $c->stash->{model_data}  = \@model_desc;

     $self->download_prediction_urls($c);
     my $download_prediction = $c->stash->{download_prediction};
     
     #get prediction populations list..     
     $self->list_of_prediction_pops($c, $pop_id, $download_prediction);
    
     my @values;
     foreach (@traits)
     {
         push @values, $c->req->param($_);
     }
      
     if (@values) 
     {
         $self->get_gebv_files_of_traits($c, \@traits, $pred_pop_id);
         my $params = $c->req->params;
         $self->gebv_rel_weights($c, $params, $pred_pop_id);
         
         $c->forward('rank_genotypes', [$pred_pop_id]);
         
         my $geno = $self->tohtml_genotypes($c);
        
         my $link = $c->stash->{ranked_genotypes_download_url};
         
         my $ret->{status} = 'failed';
         my $ranked_genos = $c->stash->{top_ranked_genotypes};
        
         if (@$ranked_genos) 
         {
             $ret->{status} = 'success';
             $ret->{genotypes} = $geno;
             $ret->{link} = $link;
         }
               
         $ret = to_json($ret);
        
         $c->res->content_type('application/json');
         $c->res->body($ret);
    }
}


sub combine_populations_confrim  :Path('/solgs/combine/populations/trait/confirm') Args(1) {
    my ($self, $c, $trait_id) = @_;
   
    my (@pop_ids, $ids);
   
    if ($trait_id =~ /\d+/)
    {
        $ids = $c->req->param('confirm_populations');
        @pop_ids = split(/,/, $ids);        
        if (!@pop_ids) {@pop_ids = $ids;}

        $c->stash->{trait_id} = $trait_id;
    } 

    my $pop_links;
    my @selected_pops_details;

    foreach my $pop_id (@pop_ids) {
    
    my $pop_rs = $c->model('solGS')->project_details($c, $pop_id);
    my $pop_details = $self->get_projects_details($c, $pop_rs);

  
    my $pop_name     = $pop_details->{$pop_id}{project_name};
    my $pop_desc     = $pop_details->{$pop_id}{project_desc};
    my $pop_year     = $pop_details->{$pop_id}{project_year};
    my $pop_location = $pop_details->{$pop_id}{project_location};
               
    my $checkbox = qq |<form> <input type="checkbox" checked="checked" name="project" value="$pop_id" /> </form> |;
    push @selected_pops_details, [ $checkbox, qq|<a href="/solgs/population/$pop_id" onclick="solGS.waitPage()">$pop_name</a>|, 
                               $pop_desc, $pop_location, $pop_year
    ];
  
    }
    
    $c->stash->{selected_pops_details} = \@selected_pops_details;    
    $c->stash->{template} = $self->template('/search/result/confirm/populations.mas');

}


sub combine_populations :Path('/solgs/combine/populations/trait') Args(1) {
    my ($self, $c, $trait_id) = @_;
   
    my (@pop_ids, $ids);
   
    if ($trait_id =~ /\d+/)
    {
        $ids = $c->req->param("$trait_id");
        @pop_ids = split(/,/, $ids);

        $self->get_trait_name($c, $trait_id);
    } 
   
    my $combo_pops_id;
    my $ret->{status} = 0;

    if (scalar(@pop_ids >1) )
    {
        $combo_pops_id =  crc(join('', @pop_ids));
        $c->stash->{combo_pops_id} = $combo_pops_id;
        $c->stash->{trait_combo_pops} = $ids;
    
        $c->stash->{trait_combine_populations} = \@pop_ids;

        $self->multi_pops_phenotype_data($c, \@pop_ids);
        $self->multi_pops_genotype_data($c, \@pop_ids);

        my $geno_files = $c->stash->{multi_pops_geno_files};
        my @g_files = split(/\t/, $geno_files);

        $self->compare_genotyping_platforms($c, \@g_files);
        my $not_matching_pops =  $c->stash->{pops_with_no_genotype_match};
     
        if (!$not_matching_pops) 
        {

            $self->cache_combined_pops_data($c);

            my $combined_pops_pheno_file = $c->stash->{trait_combined_pheno_file};
            my $combined_pops_geno_file  = $c->stash->{trait_combined_geno_file};
             
            unless (-s $combined_pops_geno_file  && -s $combined_pops_pheno_file ) 
            {
                $self->r_combine_populations($c);
                
                $combined_pops_pheno_file = $c->stash->{trait_combined_pheno_file};
                $combined_pops_geno_file  = $c->stash->{trait_combined_geno_file};
            }
                       
            if (-s $combined_pops_pheno_file > 1 && -s $combined_pops_geno_file > 1) 
            {
                my $tr_abbr = $c->stash->{trait_abbr};  
                print STDERR "\nThere are combined phenotype and genotype datasets for trait $tr_abbr\n";
                $c->stash->{data_set_type} = 'combined populations';                
                $self->get_rrblup_output($c); 
                my $analysis_result = $c->stash->{combo_pops_analysis_result};
                  
                $ret->{pop_ids}       = $ids;
                $ret->{combo_pops_id} = $combo_pops_id; 
                $ret->{status}        = $analysis_result;

              }           
        }
        else 
        {
            $ret->{not_matching_pops} = $not_matching_pops;
        }
    }
    else 
    {
        #run gs model based on a single population
        my $pop_id = $pop_ids[0];
        $ret->{redirect_url} = "/solgs/trait/$trait_id/population/$pop_id";
    }
     
    $ret = to_json($ret);
    
    $c->res->content_type('application/json');
    $c->res->body($ret);
   
}


sub display_combined_pops_result :Path('/solgs/model/combined/populations') Args(3){
    my ($self, $c, $combo_pops_id, $trait_key, $trait_id) = @_;
    
    $c->stash->{data_set_type} = 'combined populations';
    $c->stash->{combo_pops_id} = $combo_pops_id;
    
    my $pops_ids = $c->req->param('combined_populations');
    $c->stash->{trait_combo_pops} = $pops_ids;

    $self->get_trait_name($c, $trait_id);

    $self->trait_phenotype_stat($c);
    
    $self->validation_file($c);
    $self->model_accuracy($c);
    $self->gebv_kinship_file($c);
    $self->blups_file($c);
    $self->download_urls($c);
    $self->gebv_marker_file($c);
    $self->top_markers($c);
    $self->combined_pops_summary($c);

    $c->stash->{template} = $self->template('/model/combined/populations/trait.mas');
}


sub combined_pops_summary {
    my ($self, $c) = @_;
    
    my $pops_list = $c->stash->{trait_combo_pops};

    my @pops = split(/,/, $pops_list);
    
    my $desc = 'This training population is a combination of ';
    
    foreach (@pops)
    {  
        my $pr_rs = $c->model('solGS')->project_details($c, $_);

        while (my $row = $pr_rs->next)
        {
         
            my $pr_id   = $row->id;
            my $pr_name = $row->name;
            $desc .= qq | <a href="/solgs/population/$pr_id">$pr_name </a>|; 
            $desc .= $_ == $pops[-1] ? '.' : ' and ';
        }         
    }

    my $trait_abbr = $c->stash->{trait_abbr};
    my $trait_id = $c->stash->{trait_id};
    my $combo_pops_id = $c->stash->{combo_pops_id};

    my $dir = $c->{stash}->{solgs_cache_dir};

    my $geno_exp  = "genotype_data_trait_${trait_id}_${combo_pops_id}";
    my $geno_file = $self->grep_file($dir, $geno_exp);  
  
    my @geno_lines = read_file($geno_file);
    my $markers_no = scalar(split ('\t', $geno_lines[0])) - 1;

    my $pheno_exp = "phenotype_trait_${trait_abbr}_${combo_pops_id}_combined";
    my $trait_pheno_file = $self->grep_file($dir, $pheno_exp);  
    
    my @trait_pheno_lines = read_file($trait_pheno_file);
    my $stocks_no =  scalar(@trait_pheno_lines) - 1;

    my $training_pop = "Training population $combo_pops_id";

    $c->stash(markers_no   => $markers_no,
              stocks_no    => $stocks_no,
              project_desc => $desc,
              project_name => $training_pop,
        );


}


sub compare_genotyping_platforms {
    my ($self, $c,  $g_files) = @_;
 
    my $combinations = combinations($g_files, 2);
    my $combo_cnt    = combinations($g_files, 2);
    
    my $not_matching_pops;
    my $cnt = 0;
    my $cnt_pairs = 0;
    
    while ($combo_cnt->next)
    {
        $cnt_pairs++;  
    }

    while (my $pair = $combinations->next)
    {            
        open my $first_file, "<", $pair->[0] or die "cannot open genotype file:$!\n";
        my $first_markers = <$first_file>;
        $first_file->close;

       
        open my $sec_file, "<", $pair->[1] or die "cannot open genotype file:$!\n";
        my $sec_markers = <$sec_file>;
        $sec_file->close;

        my @first_geno_markers = split(/\t/, $first_markers);
        my @sec_geno_markers = split(/\t/, $sec_markers);

        my $f_cnt = scalar(@first_geno_markers);
        my $sec_cnt = scalar(@sec_geno_markers);
        
        $cnt++;

        unless (@first_geno_markers ~~ @sec_geno_markers)      
        {
            no warnings 'uninitialized';
            my $pop_id_1 = fileparse($pair->[0]);
            my $pop_id_2 = fileparse($pair->[1]);
          
            map { s/genotype_data_|\.txt//g } $pop_id_1, $pop_id_2;
                                                           
            my @pop_names;
            foreach ($pop_id_1, $pop_id_2)
            {
                my $pr_rs = $c->model('solGS')->project_details($c, $_);

                while (my $row = $pr_rs->next)
                {
                    push @pop_names,  $row->name;
                }         
            }
            
            $not_matching_pops .= '[ ' . $pop_names[0]. ' and ' . $pop_names[1] . ' ]'; 
            $not_matching_pops .= ', ' if $cnt != $cnt_pairs;       
        }       
    }

    $c->stash->{pops_with_no_genotype_match} = $not_matching_pops;
      
}


sub cache_combined_pops_data {
    my ($self, $c) = @_;

    my $trait_id = $c->stash->{trait_id};
    my $combo_pops_id = $c->stash->{combo_pops_id};

    my  $cache_pheno_data = {key       => "phenotype_data_trait_${trait_id}_${combo_pops_id}_combined",
                             file      => "phenotype_data_trait_${trait_id}_${combo_pops_id}_combined",
                             stash_key => 'trait_combined_pheno_file'
    };
      
    my  $cache_geno_data = {key       => "genotype_data_trait_${trait_id}_${combo_pops_id}_combined",
                            file      => "genotype_data_trait_${trait_id}_${combo_pops_id}_combined",
                            stash_key => 'trait_combined_geno_file'
    };

    
    $self->cache_file($c, $cache_pheno_data);
    $self->cache_file($c, $cache_geno_data);

}


sub multi_pops_pheno_files {
    my ($self, $c, $pop_ids) = @_;
 
    my $trait_id = $c->stash->{trait_id};
    my $dir = $c->stash->{solgs_cache_dir};
    my $files;
    
    if (defined reftype($pop_ids) && reftype($pop_ids) eq 'ARRAY')
    {
        foreach my $pop_id (@$pop_ids) 
        {
            my $exp = "phenotype_data_${pop_id}\.txt";
            $files .= $self->grep_file($dir, $exp);          
            $files .= "\t" unless (@$pop_ids[-1] eq $pop_id);    
        }
        $c->stash->{multi_pops_pheno_files} = $files;
    }
    else 
    {
        my $exp = "phenotype_data_${pop_ids}\.txt";
        $files = $self->grep_file($dir, $exp);
    }

    my $name = "trait_${trait_id}_multi_pheno_files";
    my $tempfile = $self->create_tempfile($c, $name);
    write_file($tempfile, $files);
 
}


sub multi_pops_geno_files {
    my ($self, $c, $pop_ids) = @_;
 
    my $trait_id = $c->stash->{trait_id};
    my $dir = $c->stash->{solgs_cache_dir};
    my $files;
    
    if (defined reftype($pop_ids) && reftype($pop_ids) eq 'ARRAY')
    {
        foreach my $pop_id (@$pop_ids) 
        {
            my $exp = "genotype_data_${pop_id}\.txt";
            $files .= $self->grep_file($dir, $exp);        
            $files .= "\t" unless (@$pop_ids[-1] eq $pop_id);    
        }
        $c->stash->{multi_pops_geno_files} = $files;
    }
    else 
    {
        my $exp = "genotype_data_${pop_ids}\.txt";
        $files = $self->grep_file($dir, $exp);
    }

    my $name = "trait_${trait_id}_multi_geno_files";
    my $tempfile = $self->create_tempfile($c, $name);
    write_file($tempfile, $files);
    
}


sub create_tempfile {
    my ($self, $c, $name) = @_;

    my ($fh, $file) = tempfile("$name-XXXXX", 
                               DIR => $c->stash->{solgs_tempfiles_dir}
        );
    
    $fh->close; 
    
    return $file;

}


sub grep_file {
    my ($self, $dir, $exp) = @_;

    opendir my $dh, $dir 
        or die "can't open $dir: $!\n";

    my ($file)  = grep { /$exp/ && -f "$dir/$_" }  readdir($dh);
    close $dh;
   
    $file = catfile($dir, $file);
    return $file;
}


sub multi_pops_phenotype_data {
    my ($self, $c, $pop_ids) = @_;
    
    if (@$pop_ids)
    {
        foreach (@$pop_ids)        
        {
            $c->stash->{pop_id} = $_;
            $self->phenotype_file($c);
        }
    }
   
    $self->multi_pops_pheno_files($c, $pop_ids);
    

}


sub multi_pops_genotype_data {
    my ($self, $c, $pop_ids) = @_;
    
    if (@$pop_ids)
    {
        foreach (@$pop_ids)        
        {
            $c->stash->{pop_id} = $_;
            $self->genotype_file($c);
        }
    }

  $self->multi_pops_geno_files($c, $pop_ids);

}


sub phenotype_graph :Path('/solgs/phenotype/graph') Args(0) {
    my ($self, $c) = @_;

    my $pop_id        = $c->req->param('pop_id');
    my $trait_id      = $c->req->param('trait_id');
    my $combo_pops_id = $c->req->param('combo_pops_id');

    $self->get_trait_name($c, $trait_id);

    $c->stash->{pop_id}        = $pop_id;
    $c->stash->{combo_pops_id} = $combo_pops_id;

    $c->stash->{data_set_type} = 'combined populations' if $combo_pops_id;
  
    $self->trait_phenodata_file($c);

    my $trait_pheno_file = $c->{stash}->{trait_phenodata_file};
    my $trait_data = $self->convert_to_arrayref($c, $trait_pheno_file);

    my $ret->{status} = 'failed';
    
    if (@$trait_data) 
    {            
        $ret->{status} = 'success';
        $ret->{trait_data} = $trait_data;
    } 
    
    $ret = to_json($ret);
        
    $c->res->content_type('application/json');
    $c->res->body($ret);

}


#generates descriptive stat for a trait phenotype data
sub trait_phenotype_stat {
    my ($self, $c) = @_;
  
    $self->trait_phenodata_file($c);
    my $trait_pheno_file = $c->{stash}->{trait_phenodata_file};
    my $trait_data = $self->convert_to_arrayref($c, $trait_pheno_file);

    my @pheno_data;   
    foreach (@$trait_data) 
    {
        unless (!$_->[0]) {
            push @pheno_data, $_->[1]; 
        }
    }

    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data(@pheno_data);
    
    my $min  = $stat->min; 
    my $max  = $stat->max; 
    my $mean = $stat->mean;
    my $std  = $stat->standard_deviation;
    my $cnt  = $stat->count;
    
    my $round = Math::Round::Var->new(0.01);
    $std  = $round->round($std);
    $mean = $round->round($mean);

    my @desc_stat =  ( [ 'No. of genotypes', $cnt ], 
                       [ 'Minimum', $min ], 
                       [ 'Maximum', $max ],
                       [ 'Mean', $mean ],
                       [ 'Standard deviation', $std ]
        );
   
    $c->stash->{descriptive_stat} = \@desc_stat;
    
}

#sends an array of trait gebv data to an ajax request
#with a population id and trait id parameters
sub gebv_graph :Path('/solgs/trait/gebv/graph') Args(0) {
    my ($self, $c) = @_;

    my $pop_id   = $c->req->param('pop_id');
    my $trait_id = $c->req->param('trait_id');
    my $combo_pops_id = $c->req->param('combo_pops_id');
    my $trait_combo_pops = $c->req->param('combined_populations');

    $c->stash->{pop_id} = $pop_id;
    $c->stash->{combo_pops_id} = $combo_pops_id;
    $c->stash->{trait_combo_pops} = $trait_combo_pops;

    $self->get_trait_name($c, $trait_id);
    
    $c->stash->{data_set_type} = 'combined populations' if $combo_pops_id;

    $self->gebv_kinship_file($c);
    my $gebv_file = $c->stash->{gebv_kinship_file}; 
    my $gebv_data = $self->convert_to_arrayref($c, $gebv_file);

    my $ret->{status} = 'failed';
    
    if (@$gebv_data) 
    {            
        $ret->{status} = 'success';
        $ret->{gebv_data} = $gebv_data;
    } 
    
    $ret = to_json($ret);
        
    $c->res->content_type('application/json');
    $c->res->body($ret);

}


sub tohtml_genotypes {
    my ($self, $c) = @_;
  
    my $genotypes = $c->stash->{top_ranked_genotypes};
    my %geno = ();

    foreach (@$genotypes)
    {
        $geno{$_->[0]} = $_->[1];
    }
    return \%geno;
}


sub get_all_traits {
    my ($self, $c) = @_;
    
    my $pheno_file = $c->stash->{phenotype_file};
    
    $self->filter_phenotype_header($c);
    my $filter_header = $c->stash->{filter_phenotype_header};
    
    open my $ph, "<", $pheno_file or die "$pheno_file:$!\n";
    my $headers = <$ph>;
    $headers =~ s/$filter_header//g;
    $ph->close;

    $self->add_trait_ids($c, $headers);
       
}


sub add_trait_ids {
    my ($self, $c, $list) = @_;   
       
    $list =~ s/\n//;
    my @traits = split (/\t/, $list);
  
    my $table = 'trait_name' . "\t" . 'trait_id' . "\n"; 
    
    my $acronym_pairs = $self->get_acronym_pairs($c);
    foreach (@$acronym_pairs)
    {
        my $trait_name = $_->[1];
        $trait_name =~ s/\n//g;
        my $trait_id = $c->model('solGS')->get_trait_id($c, $trait_name);
        $table .= $trait_name . "\t" . $trait_id . "\n";
    }

    $self->all_traits_file($c);
    my $traits_file =  $c->stash->{all_traits_file};
    
    write_file($traits_file, $table);

}


sub all_traits_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};

    my $cache_data = {key       => 'all_traits_pop' . $pop_id,
                      file      => 'all_traits_pop_' . $pop_id,
                      stash_key => 'all_traits_file'
    };

    $self->cache_file($c, $cache_data);

}


sub get_acronym_pairs {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
    
    my $dir    = $c->stash->{solgs_cache_dir};
    opendir my $dh, $dir 
        or die "can't open $dir: $!\n";

    my ($file)   =  grep(/traits_acronym_pop_${pop_id}/, readdir($dh));
    $dh->close;

    my $acronyms_file = catfile($dir, $file);
      
   
    my @acronym_pairs;
    if (-f $acronyms_file) 
    {
        @acronym_pairs =  map { [ split(/\t/) ] }  read_file($acronyms_file);   
        shift(@acronym_pairs); # remove header;
    }

    return \@acronym_pairs;

}


sub traits_acronym_table {
    my ($self, $c, $acronym_table) = @_;
    
    my $table = 'acronym' . "\t" . 'name' . "\n"; 

    foreach (keys %$acronym_table)
    {
        $table .= $_ . "\t" . $acronym_table->{$_} . "\n";
    }

    $self->traits_acronym_file($c);
    my $acronym_file =  $c->stash->{traits_acronym_file};
    
    write_file($acronym_file, $table);

}


sub traits_acronym_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};

    my $cache_data = {key       => 'traits_acronym_pop' . $pop_id,
                      file      => 'traits_acronym_pop_' . $pop_id,
                      stash_key => 'traits_acronym_file'
    };

    $self->cache_file($c, $cache_data);

}


sub analyzed_traits {
    my ($self, $c) = @_;
    
    my $model_id = $c->stash->{model_id}; 

    my $dir = $c->stash->{solgs_cache_dir};
    opendir my $dh, $dir or die "can't open $dir: $!\n";
    

    my @all_files =   grep { /gebv_kinship_[a-zA-Z0-9]/ && -f "$dir/$_" } 
                  readdir($dh); 
    closedir $dh;

    my @traits_files = grep {/($model_id)/} @all_files;
    
    my @traits;
    foreach  (@traits_files) 
    {                     
        $_ =~ s/gebv_kinship_//;
        $_ =~ s/$model_id|_//g;
        push @traits, $_;
    }

    $c->stash->{analyzed_traits} = \@traits;
    $c->stash->{analyzed_traits_files} = \@traits_files;
   
}


sub filter_phenotype_header {
    my ($self, $c) = @_;
    
    my $meta_headers = "uniquename\t|object_id\t|object_name\t|stock_id\t|stock_name\t";
    $c->stash->{filter_phenotype_header} = $meta_headers;

}


sub abbreviate_term {
    my ($self, $c, $term) = @_;
  
    my @words = split(/\s/, $term);
    
    my $acronym;
	
    if (scalar(@words) == 1) 
    {
	$acronym = shift(@words);
    }  
    else 
    {
	foreach my $word (@words) 
        {
	    if ($word=~/^\D/)
            {
		my $l = substr($word,0,1,q{}); 
		$acronym .= $l;
	    } 
            else 
            {
                $acronym .= $word;
            }

	    $acronym = uc($acronym);
	    $acronym =~/(\w+)/;
	    $acronym = $1; 
	}	   
    }
    
    return $acronym;

}


sub all_gs_traits_list {
    my ($self, $c) = @_;

    my $rs = $c->model('solGS')->all_gs_traits($c);
 
    my @all_traits;
    while (my $row = $rs->next)
    {
        my $trait_id = $row->id;
        my $trait    = $row->name;
        push @all_traits, $trait;
    }

    $c->stash->{all_gs_traits} = \@all_traits;
}


sub gs_traits_index {
    my ($self, $c) = @_;
    
    $self->all_gs_traits_list($c);
    my $all_traits = $c->stash->{all_gs_traits};
    my @all_traits =  sort{$a cmp $b} @$all_traits;
   
    my @indices = ('A'..'Z');
    my %traits_hash;
    my @valid_indices;

    foreach my $index (@indices) 
    {
        my @index_traits;
        foreach my $trait (@all_traits) 
        {
            if ($trait =~ /^$index/i) 
            {
                push @index_traits, $trait; 
		   
            }		
        }
        if (@index_traits) 
        {
            $traits_hash{$index}=[ @index_traits ];
        }
    }
           
    foreach my $k ( keys(%traits_hash)) 
    {
	push @valid_indices, $k;
    }

    @valid_indices = sort( @valid_indices );
    
    my $trait_index;
    foreach my $v_i (@valid_indices) 
    {
        $trait_index .= qq | <a href=/solgs/traits/$v_i>$v_i</a> |;
	unless ($v_i eq $valid_indices[-1]) 
        {
	    $trait_index .= " | ";
	}	 
    }
   
    $c->stash->{gs_traits_index} = $trait_index;
   
}


sub traits_starting_with {
    my ($self, $c, $index) = @_;

    $self->all_gs_traits_list($c);
    my $all_traits = $c->stash->{all_gs_traits};
   
    my $trait_gr = [
        sort { $a cmp $b  }
        grep { /^$index/i }
        uniq @$all_traits
        ];

    $c->stash->{trait_subgroup} = $trait_gr;
}


sub hyperlink_traits {
    my ($self, $c, $traits) = @_;

    my @traits_urls;
    foreach my $tr (@$traits)
    {
        push @traits_urls, [ qq | <a href="/solgs/search/result/traits/$tr">$tr</a> | ];
    }
    $c->stash->{traits_urls} = \@traits_urls;
}


sub gs_traits : Path('/solgs/traits') Args(1) {
    my ($self, $c, $index) = @_;
    
    if ($index =~ /^\w{1}$/) 
    {
        $self->traits_starting_with($c, $index);
        my $traits_gr = $c->stash->{trait_subgroup};
        
        $self->hyperlink_traits($c, $traits_gr);
        my $traits_urls = $c->stash->{traits_urls};
        
        $c->stash( template    => $self->template('/search/traits/list.mas'),
                   index       => $index,
                   traits_list => $traits_urls
            );
    }
    else 
    {
        $c->forward('search');
    }
}


sub phenotype_file {
    my ($self, $c) = @_;
    my $pop_id     = $c->stash->{pop_id};
    
    die "Population id must be provided to get the phenotype data set." if !$pop_id;
  
    my $file_cache  = Cache::File->new(cache_root => $c->stash->{solgs_cache_dir});
    $file_cache->purge();
   
    my $key        = "phenotype_data_" . $pop_id;
    my $pheno_file = $file_cache->get($key);

    unless ($pheno_file)
    {  
        $pheno_file = catfile($c->stash->{solgs_cache_dir}, "phenotype_data_" . $pop_id . ".txt");
        $c->model('solGS')->phenotype_data($c, $pop_id);
        my $data = $c->stash->{phenotype_data};
        
        $data = $self->format_phenotype_dataset($c, $data);
        write_file($pheno_file, $data);

        $file_cache->set($key, $pheno_file, '30 days');
    }
   
    $c->stash->{phenotype_file} = $pheno_file;

}


sub format_phenotype_dataset {
    my ($self, $c, $data) = @_;
    
    my @rows = split (/\n/, $data);
    
    $rows[0] =~ s/SP:\d+\|//g;  
    $rows[0] =~ s/\w+:\w+\|//g;
   

    my @headers = split(/\t/, $rows[0]);
    
    my $header;   
    my %acronym_table;

    $self->filter_phenotype_header($c);
    my $filter_header = $c->stash->{filter_phenotype_header};
    $filter_header =~ s/\t//g;

    my $cnt = 0;
    foreach my $trait_name (@headers)
    {
        $cnt++;
        
        my $abbr = $self->abbreviate_term($c, $trait_name);
        $header .= $abbr;
       
        unless ($cnt == scalar(@headers))
        {
            $header .= "\t";
        }
        
        $abbr =~ s/$filter_header//g;
        $acronym_table{$abbr} = $trait_name if $abbr;
    }
    
    $rows[0] = $header;
    
    foreach (@rows)
    {
        $_ =~ s/\s+plot//g;
        $_ .= "\n";
    }
    
    $self->traits_acronym_table($c, \%acronym_table);

    return \@rows;
}


sub genotype_file  {
    my ($self, $c, $pred_pop_id) = @_;
    my $pop_id  = $c->stash->{pop_id};
    
    if ($pred_pop_id) 
    {       
        $pop_id = $c->stash->{prediction_pop_id};
    }
    
    die "Population id must be provided to get the genotype data set." if !$pop_id;
  
    my $file_cache  = Cache::File->new(cache_root => $c->stash->{solgs_cache_dir});
    $file_cache->purge();
   
    my $key        = "genotype_data_" . $pop_id;
    my $geno_file = $file_cache->get($key);

    unless ($geno_file)
    {  
        $geno_file = catfile($c->stash->{solgs_cache_dir}, "genotype_data_" . $pop_id . ".txt");
        $c->model('solGS')->genotype_data($c, $pop_id);
        my $data = $c->stash->{genotype_data};
        
        write_file($geno_file, $data);

        $file_cache->set($key, $geno_file, '30 days');
    }
   
    if ($pred_pop_id) 
    {
        $c->stash->{pred_genotype_file} = $geno_file;
    }
    else 
    {
        $c->stash->{genotype_file} = $geno_file; 
    }
   
}


sub get_rrblup_output :Private{
    my ($self, $c) = @_;
    
    my $pop_id      = $c->stash->{pop_id};
    my $trait_abbr  = $c->stash->{trait_abbr};
    my $trait_name  = $c->stash->{trait_name};
    
    my $data_set_type = $c->stash->{data_set_type};

    my ($traits_file, @traits, @trait_pages);
    my $prediction_id = $c->stash->{prediction_pop_id};
   
    if ($trait_abbr)     
    {
        $self->run_rrblup_trait($c, $trait_abbr);
    }
    else 
    {    
        $traits_file = $c->stash->{selected_traits_file};
        my $content  = read_file($traits_file);
     
        if ($content =~ /\t/)
        {
            @traits = split(/\t/, $content);
        }
        else
        {
            push  @traits, $content;
        }
            
       foreach my $tr (@traits) 
       { 
           my $acronym_pairs = $self->get_acronym_pairs($c);
           my $trait_name;
           if ($acronym_pairs)
           {
               foreach my $r (@$acronym_pairs) 
               {
                   if ($r->[0] eq $tr) 
                   {
                       $trait_name = $r->[1];
                       $trait_name =~ s/\n//g;
                       $c->stash->{trait_name} = $trait_name;
                       $c->stash->{trait_abbr} = $r->[0];
                   }
               }
           }    
           
           $self->run_rrblup_trait($c, $tr);
           
           my $trait_id = $c->model('solGS')->get_trait_id($c, $trait_name);
           push @trait_pages, [ qq | <a href="/solgs/trait/$trait_id/population/$pop_id" onclick="solGS.waitPage()">$tr</a>| ];
       }    
    }

    $c->stash->{combo_pops_analysis_result} = 0;

    if($data_set_type !~ /combined populations/) 
    {
        if (scalar(@traits) == 1) 
        {
            $self->gs_files($c);
            $c->stash->{template} = $self->template('population/trait.mas');
        }
    
    
        if (scalar(@traits) > 1)    
        {
            $c->stash->{model_id} = $pop_id;
            $self->analyzed_traits($c);
            $c->stash->{template}    = $self->template('/population/multiple_traits_output.mas'); 
            $c->stash->{trait_pages} = \@trait_pages;
        }
    }
    else 
    {
        $c->stash->{combo_pops_analysis_result} = 1;
    }

}


sub run_rrblup_trait {
    my ($self, $c, $trait_abbr) = @_;
    
    my $pop_id     = $c->stash->{pop_id};
    my $trait_name = $c->stash->{trait_name};
    my $trait_abbr = $c->stash->{trait_abbr};
    my $data_set_type = $c->stash->{data_set_type};

    my $trait_id = $c->model('solGS')->get_trait_id($c, $trait_name);
    $c->stash->{trait_id} = $trait_id; 
                                
  
    if ($data_set_type =~ /combined populations/i) 
    {
        
       #  my $name = "trait_${trait_id}_combined_pops";

#         my $file = $self->create_tempfile($c, $name);    
#         $c->stash->{trait_file} = $file;       
#         write_file($file, $trait_abbr);

        my $prediction_id = $c->stash->{prediction_pop_id};

        $self->output_files($c);

        my $combined_pops_pheno_file = $c->stash->{trait_combined_pheno_file};
        my $combined_pops_geno_file  = $c->stash->{trait_combined_geno_file};
              
        my $trait_info   = $trait_id . "\t" . $trait_abbr;     
        my $trait_file  = $self->create_tempfile($c, "trait_info_${trait_id}");
        write_file($trait_file, $trait_info);

        my $dataset_file  = $self->create_tempfile($c, "dataset_info_${trait_id}");
        write_file($dataset_file, $data_set_type);

        my $input_files = join("\t",
                                   $c->stash->{trait_combined_pheno_file},
                                   $c->stash->{trait_combined_geno_file},
                                   $trait_file,
                                   $dataset_file
            );

        my $input_file = $self->create_tempfile($c, "input_files_combo_${trait_abbr}");
        write_file($input_file, $input_files);

        if ($c->stash->{prediction_pop_id})
        {       
            $c->stash->{input_files} = $input_file;
            $self->output_files($c);
            $self->run_rrblup($c); 
        }
        else
        {       
            if (-s $c->stash->{gebv_kinship_file} == 0 ||
                -s $c->stash->{gebv_marker_file}  == 0 ||
                -s $c->stash->{validation_file}   == 0       
                )
            {  
                $c->stash->{input_files} = $input_file;
                $self->output_files($c);
                $self->run_rrblup($c); 
       
            }
        }        
    }
    else 
    {
        my $name  = "trait_info_${trait_id}_pop_${pop_id}"; 
    
        my $trait_info = $trait_id . "\t" . $trait_abbr;
        my $file = $self->create_tempfile($c, $name);    
        $c->stash->{trait_file} = $file;       
        write_file($file, $trait_info);

        my $prediction_id = $c->stash->{prediction_pop_id};

        $self->output_files($c);
        
        if ($prediction_id)
        { 
            my $identifier =  $pop_id . '_' . $prediction_id;
            $self->prediction_pop_gebvs_file($c, $identifier, $trait_id);
            my $pred_pop_gebvs_file = $c->stash->{prediction_pop_gebvs_file};

            unless (-s $pred_pop_gebvs_file != 0) 
            {
                $self->input_files($c);            
                $self->run_rrblup($c); 
            }
        }
        else
        {   
            $self->output_files($c);
        
            if (-s $c->stash->{gebv_kinship_file} == 0 ||
                -s $c->stash->{gebv_marker_file}  == 0 ||
                -s $c->stash->{validation_file}   == 0       
                )
            {  
                $self->input_files($c);            
                $self->output_files($c);
                $self->run_rrblup($c);        
            }
        }
    }
    
}


sub run_rrblup  {
    my ($self, $c) = @_;
   
    #get all input files & arguments for rrblup, 
    #run rrblup and save output in solgs user dir
    my $pop_id        = $c->stash->{pop_id};
    my $trait_id      = $c->stash->{trait_id};
    my $input_files   = $c->stash->{input_files};
    my $output_files  = $c->stash->{output_files};
    my $data_set_type = $c->stash->{data_set_type};

    if ($data_set_type !~ /combined populations/)
    {
        die "\nCan't run rrblup without a population id." if !$pop_id;   

    }

    die "\nCan't run rrblup without a trait id." if !$trait_id;
   
    die "\nCan't run rrblup without input files." if !$input_files;
    die "\nCan't run rrblup without output files." if !$output_files;    
    
    if ($data_set_type !~ /combined populations/)
    {
       
        $c->stash->{r_temp_file} = "gs-rrblup-${trait_id}-${pop_id}";
    }
    else
    {
        my $combo_pops = $c->stash->{trait_combo_pops};
        $combo_pops    = join('', split(/,/, $combo_pops));
        my $combo_identifier = crc($combo_pops);

        $c->stash->{r_temp_file} = "gs-rrblup-combo-${trait_id}-${combo_identifier}"; 
    }
   
    $c->stash->{r_script}    = 'R/gs.r';
    $self->run_r_script($c);
}


sub r_combine_populations  {
    my ($self, $c) = @_;
    
    my $combo_pops_id = $c->stash->{combo_pops_id};
    my $trait_id     = $c->stash->{trait_id};
    my $trait_abbr   = $c->stash->{trait_abbr};
    my $trait_info   = $trait_id . "\t" . $trait_abbr;
    
    my $trait_file  = $self->create_tempfile($c, "trait_info_${trait_id}");
    write_file($trait_file, $trait_info);

    my $pheno_files = $c->stash->{multi_pops_pheno_files};
    my $geno_files  = $c->stash->{multi_pops_geno_files};
        
    my $input_files = join ("\t",
                            $pheno_files,
                            $geno_files,
                            $trait_file,
   
        );

    my $combined_pops_pheno_file = $c->stash->{trait_combined_pheno_file};
    my $combined_pops_geno_file  = $c->stash->{trait_combined_geno_file};
    
    my $output_files = join ("\t", 
                             $combined_pops_pheno_file,
                             $combined_pops_geno_file,
        );
                             
     
    my $tempfile_input = $self->create_tempfile($c, "input_files_${trait_id}_combine"); 
    write_file($tempfile_input, $input_files);

    my $tempfile_output = $self->create_tempfile($c, "output_files_${trait_id}_combine"); 
    write_file($tempfile_output, $output_files);
        
    die "\nCan't call combine populations R script without a trait id." if !$trait_id;
    die "\nCan't call combine populations R script without input files." if !$input_files;
    die "\nCan't call combine populations R script without output files." if !$output_files;    
    
    $c->stash->{input_files}  = $tempfile_input;
    $c->stash->{output_files} = $tempfile_output;
    $c->stash->{r_temp_file}  = "combine-pops-${trait_id}";
    $c->stash->{r_script}     = 'R/combine_populations.r';
    
    $self->run_r_script($c);

    

}


sub run_r_script {
    my ($self, $c) = @_;
    
    my $r_script     = $c->stash->{r_script};
    my $input_files  = $c->stash->{input_files};
    my $output_files = $c->stash->{output_files};
    my $r_temp_file  = $c->stash->{r_temp_file};
  
    CXGN::Tools::Run->temp_base($c->stash->{solgs_tempfiles_dir});
    my ( $r_in_temp, $r_out_temp ) =
        map 
    {
        my ( undef, $filename ) =
            tempfile(
                catfile(
                    CXGN::Tools::Run->temp_base(),
                    "${r_temp_file}-$_-XXXXXX",
                ),
            );
        $filename
    } 
    qw / in out /;
    {
        my $r_cmd_file = $c->path_to($r_script);
        copy($r_cmd_file, $r_in_temp)
            or die "could not copy '$r_cmd_file' to '$r_in_temp'";
    }

    try 
    {
        my $r_process = CXGN::Tools::Run->run_cluster(
            'R', 'CMD', 'BATCH',
            '--slave',
            "--args $input_files $output_files",
            $r_in_temp,
            $r_out_temp,
            {
                working_dir => $c->stash->{solgs_tempfiles_dir},
                max_cluster_jobs => 1_000_000_000,
            },
            );

        $r_process->wait; 
    }
    catch 
    {
        my $err = $_;
        $err =~ s/\n at .+//s; 
        try
        { 
            $err .= "\n=== R output ===\n".file($r_out_temp)->slurp."\n=== end R output ===\n" 
        };
       
        
        $c->throw(is_client_error   => 1,
                  title             => "$r_script Script Error",
                  public_message    => "There is a problem running $r_script on this dataset!",	     
                  notify            => 1, 
                  developer_message => $err,
            );
    }

}
 
 
sub get_solgs_dirs {
    my ($self, $c) = @_;
   
    my $solgs_dir       = $c->config->{solgs_dir};
    my $solgs_cache     = catdir($solgs_dir, 'cache'); 
    my $solgs_tempfiles = catdir($solgs_dir, 'tempfiles');
  
    mkpath ([$solgs_dir, $solgs_cache, $solgs_tempfiles], 0, 0755);
   
    $c->stash(solgs_dir           => $solgs_dir, 
              solgs_cache_dir     => $solgs_cache, 
              solgs_tempfiles_dir => $solgs_tempfiles
        );

}


sub cache_file {
    my ($self, $c, $cache_data) = @_;
    
    my $solgs_cache = $c->stash->{solgs_cache_dir};
    my $file_cache  = Cache::File->new(cache_root => $solgs_cache);
    $file_cache->purge();

    my $file  = $file_cache->get($cache_data->{key});

    unless ($file)
    {      
        $file = catfile($solgs_cache, $cache_data->{file});
        write_file($file);
        $file_cache->set($cache_data->{key}, $file, '30 days');
    }

    $c->stash->{$cache_data->{stash_key}} = $file;
}


sub load_yaml_file {
    my ($self, $c, $file) = @_;

    $file =~ s/\.\w+//;
    $file =~ s/(^\/)//;
   
    my $form = $self->form;
    my $yaml_dir = '/root/forms/solgs';
 
    $form->load_config_filestem($c->path_to(catfile($yaml_dir, $file)));
    $form->process;
    
    $c->stash->{form} = $form;
 
}


sub template {
    my ($self, $file) = @_;

    $file =~ s/(^\/)//; 
    my $dir = '/solgs';
 
    return  catfile($dir, $file);

}


sub default :Path {
    my ( $self, $c ) = @_; 
    $c->forward('search');
}



=head2 end

Attempt to render a view, if needed.

=cut

sub render : ActionClass('RenderView') {}


sub end : Private {
    my ( $self, $c ) = @_;

    return if @{$c->error};

    # don't try to render a default view if this was handled by a CGI
    $c->forward('render') unless $c->req->path =~ /\.pl$/;

    # enforce a default text/html content type regardless of whether
    # we tried to render a default view
    $c->res->content_type('text/html') unless $c->res->content_type;

    # insert our javascript packages into the rendered view
    if( $c->res->content_type eq 'text/html' ) {
        $c->forward('/js/insert_js_pack_html');
        $c->res->headers->push_header('Vary', 'Cookie');
    } else {
        $c->log->debug("skipping JS pack insertion for page with content type ".$c->res->content_type)
            if $c->debug;
    }

}

=head2 auto

Run for every request to the site.

=cut

sub auto : Private {
    my ($self, $c) = @_;
    CatalystX::GlobalContext->set_context( $c );
    $c->stash->{c} = $c;
    weaken $c->stash->{c};

    $self->get_solgs_dirs($c);
    # gluecode for logins
    #
#  #   unless( $c->config->{'disable_login'} ) {
   #      my $dbh = $c->dbc->dbh;
   #      if ( my $sp_person_id = CXGN::Login->new( $dbh )->has_session ) {

   #          my $sp_person = CXGN::People::Person->new( $dbh, $sp_person_id);

   #          $c->authenticate({
   #              username => $sp_person->get_username(),
   #              password => $sp_person->get_password(),
   #          });
   #      }
   # }

    return 1;
}




=head1 AUTHOR

Isaak Y Tecle <iyt2@cornell.edu>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
