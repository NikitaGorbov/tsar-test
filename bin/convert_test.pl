#!perl
use strict;
use autodie qw(open);
use File::Spec::Functions qw(catfile splitpath catpath);
use File::Path qw(make_path);
use File::Copy;

my $res_dir='converted_tests';

@ARGV or die "usage: convert_test.pl *.conf\n";
my @confs = map glob, @ARGV;

for my $conf (@confs) {
  eval {
    make_test($conf);
  };
  if ($@) {
    warn $@;
  }
}

sub make_test
{
  my $conf = shift;
  (my $name = $conf) =~ s/\.conf$// or die "$conf is not a task.conf\n";

  ## read config file ##
  open my $f, '<', $conf;
  my @lines = <$f>;
  close $f;

  mk_task($name, \@lines, $res_dir);
}

sub mk_task
{
  my ($name, $lines, $res_dir) = @_;

  my @required_vars = qw(options);
  my @uniq_vars = (@required_vars, qw(name));

  ## parse current task configuration file ##
  my %vars;
  my $qr_vars = join '|', @uniq_vars;
  for (@$lines) {
    chomp;
    next if /^\s*$/;
    if (/^($qr_vars)/) { $vars{$1} = $_ }
    elsif ($_ eq q(plugin = TsarPlugin)) {}
    elsif ($_ eq q(sample = $name.c)) {}
    elsif ($_ eq q(run = "$tsar $sample $options")) {}
    elsif ($_ eq q(run = "$tsar $sample $options | -check-prefix=SAFE")) { goto \&mk_task_safe }
    elsif ($_ eq q(      "$tsar $sample $options -fignore-redundant-memory=strict | -check-prefix=REDUNDANT")){ goto \&mk_task_redundant }
    elsif ($_ eq q(suffix = tfm)) { goto \&mk_task_transform }
    else {
      die "unexpected content in '$name.conf':\n$_\n"
    }
  }
  exists $vars{$_} or die "$name.conf: '$_' is not set\n" for @required_vars;

  my $tdir = catfile($res_dir, $name);
  copy_src($tdir, {"$name.c" => 'main.c'});
  gen_task(catfile($tdir, 'tsar.conf'), @vars{qw(name options)});
  mk_sample("$name.c", catfile($tdir, 'sample'), 'CHECK');
}

sub mk_task_safe
{
  my ($name, $lines, $res_dir) = @_;

  my @required_vars = qw(options);
  my @uniq_vars = (@required_vars, qw(name));

  ## parse current task configuration file ##
  my %vars;
  my $qr_vars = join '|', @uniq_vars;
  my @run;
  for (@$lines) {
    chomp;
    next if /^\s*$/;
    if (/^($qr_vars)/) { $vars{$1} = $_ }
    elsif ($_ eq q(plugin = TsarPlugin)) {}
    elsif ($_ eq q(sample = $name.c)) {}
    elsif (/^(?:\s*run\s*=)?\s*\"\$tsar \$sample \$options( [^|]*?)\s*\| -check-prefix=(\S+)\s*"$/) {
      push @run, {
        name_suffix => "-$2",
        check_prefix => $2,
        run => q(run = "$tsar $sample $options"),
        add_opts => $1 ? " $1" : '',
      }
    }
    else {
      die "unexpected content in '$name.conf':\n$_\n"
    }
  }
  exists $vars{$_} or die "$name.conf: '$_' is not set\n" for @required_vars;

  (my $src_name = $name) =~ s/\.safe$// or die "unexpeced name '$name' for the SAFE test";
  for (@run) {
    my $tdir = catfile($res_dir, $name.$_->{name_suffix});
    copy_src($tdir, {"$src_name.c" => 'main.c'});
    gen_task(catfile($tdir, 'tsar.conf'), $vars{name}, $vars{options}.$_->{add_opts});
    mk_sample("$src_name.c", catfile($tdir, 'sample'), $_->{check_prefix}||'CHECK');
  }
}

sub mk_task_redundant
{
  my ($name, $lines, $res_dir) = @_;

  my @required_vars = qw(options);
  my @uniq_vars = (@required_vars, qw(name));

  ## parse current task configuration file ##
  my %vars;
  my $qr_vars = join '|', @uniq_vars;
  my @run;
  for (@$lines) {
    chomp;
    next if /^\s*$/;
    if (/^($qr_vars)/) { $vars{$1} = $_ }
    elsif ($_ eq q(plugin = TsarPlugin)) {}
    elsif ($_ eq q(sample = $name.c)) {}
    elsif ($_ eq q(run = "$tsar $sample $options")) {push @run, {name_suffix => '', run => $_, add_opts => ''}}
    elsif (/^\s*\"\$tsar \$sample \$options( [^|]*?)\s*\| -check-prefix=(\S+)\s*"$/) {
      push @run, {
        name_suffix => "-$2",
        check_prefix => $2,
        run => q(run = "$tsar $sample $options"),
        add_opts => $1,
      }
    }
    else {
      die "unexpected content in '$name.conf':\n$_\n"
    }
  }
  exists $vars{$_} or die "$name.conf: '$_' is not set\n" for @required_vars;

  for (@run) {
    my $tdir = catfile($res_dir, $name.$_->{name_suffix});
    copy_src($tdir, {"$name.c" => 'main.c'});
    gen_task(catfile($tdir, 'tsar.conf'), $vars{name}, $vars{options}.$_->{add_opts});
    mk_sample("$name.c", catfile($tdir, 'sample'), $_->{check_prefix}||'CHECK');
  }
}

sub mk_task_transform
{
  my ($name, $lines, $res_dir) = @_;

  my @required_vars = qw(options);
  my @uniq_vars = (@required_vars, qw(name));

  ## parse current task configuration file ##
  my %vars;
  my $suffix;
  my $qr_vars = join '|', @uniq_vars;
  for (@$lines) {
    chomp;
    next if /^\s*$/;
    if (/^($qr_vars)/) { $vars{$1} = $_ }
    elsif ($_ eq q(plugin = TsarPlugin)) {}
    elsif ($_ eq q(sample = $name.c)) {}
    elsif ($_ eq q(run = "$tsar $sample $options")) {}
    elsif (/^suffix =\s*(\S+)/) { $suffix = $1 }
    elsif ($_ eq q(sample_diff = $name.$suffix.c)) {}
    else {
      die "unexpected content in '$name.conf':\n$_\n"
    }
  }
  exists $vars{$_} or die "$name.conf: '$_' is not set\n" for @required_vars;

  #$vars{options} =~ s/(\s*-output-suffix=)\$suffix/$1/;

  my $tdir = catfile($res_dir, $name);
  copy_src_transform($tdir, {"$name.c" => 'main.c'}, 'CHECK');
  my $src_tfm = "$name.$suffix.c";
  undef $src_tfm if !-e $src_tfm;
  gen_task_transform(catfile($tdir, 'tsar.conf'), @vars{qw(name options)}, $src_tfm);
  mk_sample_transform("$name.c", catfile($tdir, 'sample'), 'CHECK', $src_tfm);
}

# copy_src($tdir, {'test_name.c' => 'main.c'})
sub copy_src
{
  my ($dir, $src_map) = @_;
  -e or die "$_ does not exist" for keys %$src_map;
  make_path($dir);
  while (my ($src, $dst) = each %$src_map) {
    $dst = catfile($dir, $dst);
    copy($src, $dst) or die "cannot copy file '$src' to '$dst'\n";
  }
}

sub copy_src_transform
{
  my ($dir, $src_map, $discard_prefix) = @_;
  -e or die "$_ does not exist" for keys %$src_map;
  make_path($dir);
  while (my ($src, $dst) = each %$src_map) {
    $dst = catfile($dir, $dst);
    open my $f, '<', $src;
    my @lines = grep !m~^(?://|!|C)$discard_prefix~, <$f>;
    close $f; undef $f;
    open my $f, '>', $dst;
    print $f @lines;
    close $f;
  }
}

sub mk_sample
{
  my ($src, $dst_dir, $check_prefix) = @_;
  copy_src($dst_dir, {$src => 'main.c'});
  open my $f, '<', $src;
  my @lines = map {s/$src/main.c/g; $_} map {s~^(?://|!|C)$check_prefix: ~~ ? $_ : ()} <$f>;
  close $f;

  my $fname = catfile($dst_dir, 'output.txt');
  undef $f;
  open $f, '>', $fname;
  print $f @lines;
  close $f;
}

sub mk_sample_transform
{
  my ($src, $dst_dir, $check_prefix, $src_tfm) = @_;
  copy_src_transform($dst_dir, {$src => 'main.c', defined $src_tfm ? ($src_tfm => 'main.tfm.c') : ()}, $check_prefix);
  open my $f, '<', $src;
  my @lines = map {s/$src/main.c/g; $_} map {s~^(?://|!|C)$check_prefix: ~~ ? $_ : ()} <$f>;
  chomp $lines[-1] if @lines == 1;
  close $f;

  my $fname = catfile($dst_dir, 'output.txt');
  undef $f;
  open $f, '>', $fname;
  print $f @lines;
  close $f;
}

sub gen_task
{
  my ($conf, $name, $options) = @_;

  ## generate new config files ##
  open my $f, '>', $conf;
  print $f
'plugin = TsarPlugin
'.($name ? $name : '').'
sources = main.c
copy = $sources
sample = $copy output.txt
clean = $sample
'.$options.'
run = "$tsar $sources $options >output.txt 2>&1"
';
  close $f;
}

sub gen_task_transform
{
  my ($conf, $name, $options, $src_tfm) = @_;

  ## generate new config files ##
  open my $f, '>', $conf;
  print $f
'plugin = TsarPlugin
'.($name ? $name : '').'
suffix = tfm
sources = main.c
copy = $sources
sample = $copy '.(defined $src_tfm ? 'main.$suffix.c ' : '').'output.txt
clean = $sample
'.$options.'
run = "$tsar $sources $options 2>&1 | perl -p ../output_filter.pl >output.txt"
';
  close $f;

  ## generate output_filter.pl ##
  my $fname = catpath((splitpath($conf))[0,1], 'output_filter.pl');
  undef $f;
  open $f, '>', $fname;
  print $f <<'EOF';
use Cwd;
use File::Spec::Functions;
(my $s = canonpath(cwd)) =~ s/\\/\\\\/g;
s/$s(:?\\|\/)//g;
EOF
  close $f;
}
