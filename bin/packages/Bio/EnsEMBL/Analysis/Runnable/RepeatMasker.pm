# Ensembl module for Bio::EnsEMBL::Analysis::Runnable::RepeatMasker
#
# Copyright (c) 2004 Ensembl
#

=head1 NAME

Bio::EnsEMBL::Analysis::Runnable::RepeatMasker

=head1 SYNOPSIS

  my $repeat_masker = Bio::EnsEMBL::Analysis::Runnable::RepeatMasker->
  new(
      -query => $slice,
      -program => 'repeatmasker',
      -options => '-low'
     );
  $repeat_masker->run;
  my @repeats = @{$repeat_masker->output};

=head1 DESCRIPTION

RepeatMasker expects to run the program RepeatMasker
and produce RepeatFeatures which can be stored in the repeat_feature
and repeat_consensus tables in the core database


=head1 CONTACT

Post questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=cut


package Bio::EnsEMBL::Analysis::Runnable::RepeatMasker;

use strict;
use warnings;

use Bio::EnsEMBL::Analysis::Runnable;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use vars qw(@ISA);

@ISA = qw(Bio::EnsEMBL::Analysis::Runnable);



sub new {
  my ($class,@args) = @_;
  
  my $self = $class->SUPER::new(@args);

  ######################
  #SETTING THE DEFAULTS#
  ######################
  $self->program('RepeatMasker') if(!$self->program);
  ######################

  return $self;
}

=head2 run_analysis

  Arg [1]   : Bio::EnsEMBL::Analysis::Runnable::RepeatMasker
  Arg [2]   : string, program name
  Function  : constructs a commandline and runs the program passed
  in, the generic method in Runnable isnt used as RepeatMasker doesnt
  fit this module
  Returntype: none
  Exceptions: throws if run failed because sysetm doesnt
  return 0 or the output file doesnt exist
  Example   : 

=cut


sub run_analysis{
  my ($self, $program) = @_;
  if(!$program){
    $program = $self->program;
  }
  throw($program." is not executable RepeatMasker::run_analysis ") 
    unless($program && -x $program);
  my $cmd = $self->program." ";
  $cmd .= $self->options." " if($self->options);
  $cmd .= $self->queryfile;
  print "Running analysis ".$cmd."\n";
  system($cmd) == 0 or throw("FAILED to run ".$cmd.
                             " RepeatMasker:run_analysis");
  foreach my $file(glob $self->queryfile."*"){
    $self->files_to_delete($file);
  }
  if(! -e $self->resultsfile){
    throw("FAILED to run repeatmasker on ".$self->queryfile." ".
          $self->resultsfile." has not been produced ".
          "RepeatMasker:run_analysis");
  }
}



=head2 parse_results

  Arg [1]   : Bio::EnsEMBL::Analysis::Runnable::RepeatMasker
  Arg [2]   : string, filename
  Function  : open and parse the results file into repeat
  features
  Returntype: none 
  Exceptions: throws on failure to open or close output file
  Example   : 

=cut



sub parse_results{
  my ($self, $results) =  @_;
  if(!$results){
    $results = $self->resultsfile;
  }
  my $feature_factory = $self->feature_factory;
  open(OUT, "<".$results) or throw("FAILED to open ".$results.
                                   "RepeatMasker:parse_results");
  REPEAT:while(<OUT>){
      if (/no repetitive sequences detected/) {
        print "RepeatMasker didn't find any repetitive sequences";
        last REPEAT; #no repeats found no point carrying on
      }
      if(/only contains ambiguous bases/){
        print "Sequence contains too many N's \n";
        last REPEAT;
      }
      my @columns;
      if(/\d+/){ #ignoring introductory lines
        chomp;
        @columns = split;
        pop @columns if $columns[-1] eq '*';
        #if (@columns != 15 || @columns != 14) {
        #  throw("Can't parse repeatmasker output unexpected number ".
        #        "of columns in the output ".@columns." in ".$_." ".
        #        "RepeatMasker:parse_results");
        #}

        my ($score, $name, $start, $end, $strand,
            $repeat_name, $repeat_class, $repeatmunge, $repeatmunge2); 
        if(@columns == 15){
          ($score, $name, $start, $end, $strand,
           $repeat_name, $repeat_class) =  @columns[0, 4, 5, 6, 8, 9, 10];
        }elsif(@columns == 14){
          ($score, $name, $start, $end, $strand,
           $repeatmunge,$repeatmunge2) =  @columns[0, 4, 5, 6, 8, 9, 10];
          if ($repeatmunge =~ /(\S+)(LINE\S+)/) {
            $repeatmunge =~ /(\S+)(LINE\S+)/;
            $repeat_name = $1;
            $repeat_class = $2;
          } elsif ($repeatmunge2 eq 'Unknown') {
            print "Unknown repeat name\n";
            $repeat_name = 'Unknown';
          } else {
            throw("Can't parse repeatmasker output for line = $_\n");
          }
          if(!$repeat_class){
            $repeat_class = 'UNK';
          }
        }else{
          throw("Can't parse repeatmasker output unexpected number ".
                "of columns in the output ".@columns." in ".$_." ".
                "RepeatMasker:parse_results");
        }
        my $start_column;
        if($strand eq '+'){ 
          $start_column = 11;
          $strand = 1;
        }
        if($strand eq 'C'){
          $start_column = 13;
          $strand = -1;
        }#the location of the start and end inside the repeat 
        #is different depending on the strand
        my $repeat_start = $columns[$start_column];
        my $repeat_end = $columns[12];
        if($repeat_end < $repeat_start){
          my $temp_end = $repeat_start;
          $repeat_start = $repeat_end;
          $repeat_end = $temp_end;
        }
        my $rc = $feature_factory->create_repeat_consensus($repeat_name, 
                                                           $repeat_class);
        my $rf = $feature_factory->create_repeat_feature
          ($start, $end, $strand, $score, 
           $repeat_start, $repeat_end, 
           $rc, $self->query);
        
        $self->output([$rf]);
      }
    }
  close(OUT) or throw("FAILED to close ".$results.
                      "RepeatMasker:parse_results");
}


1;
