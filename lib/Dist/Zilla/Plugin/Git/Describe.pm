package Dist::Zilla::Plugin::Git::Describe;
# ABSTRACT: add the results of `git describe` (roughly) to your main module
use Moose;
with(
  'Dist::Zilla::Role::FileMunger',
  'Dist::Zilla::Role::PPI',
);

use Git::Wrapper;
use Try::Tiny;

use namespace::autoclean;

=head1 SYNOPSIS

in dist.ini

  [Git::Describe]

=head1 DESCRIPTION

This plugin will add the long-form git commit description for the current repo
to the dist's main module as a comment.  It may change, in the future, to put
things in a package variable, or to provide an option.

It inserts this in the same place that PkgVersion would insert a version.

=cut

sub munge_files {
  my ($self) = @_;

  my $file = $self->zilla->main_module;

  my $document = $self->ppi_document_for_file($file);

  if ($self->document_assigns_to_variable($document, '$VERSION')) {
    $self->log([ 'skipping %s: assigns to $VERSION', $file->name ]);
    return;
  }

  return unless my $package_stmts = $document->find('PPI::Statement::Package');

  my $git  = Git::Wrapper->new( $self->zilla->root );
  my @lines = $git->describe({ long => 1, always => 1 });

  my $desc = $lines[0];

  my %seen_pkg;

  for my $stmt (@$package_stmts) {
    my $package = $stmt->namespace;

    if ($seen_pkg{ $package }++) {
      $self->log([ 'skipping package re-declaration for %s', $package ]);
      next;
    }

    if ($stmt->content =~ /package\s*(?:#.*)?\n\s*\Q$package/) {
      $self->log([ 'skipping private package %s in %s', $package, $file->name ]);
      next;
    }

    my $perl = "# git description: $desc\n";

    my $version_doc = PPI::Document->new(\$perl);
    my @children = $version_doc->children;

    $self->log_debug([
      'adding git description comment to %s in %s',
      $package,
      $file->name,
    ]);

    Carp::carp("error inserting git description in " . $file->name)
      unless $stmt->insert_after($children[0]->clone)
      and    $stmt->insert_after( PPI::Token::Whitespace->new("\n") );
  }

  $self->save_ppi_document_to_file($document, $file);
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 SEE ALSO

L<PodVersion|Dist::Zilla::Plugin::PkgVersion>

=cut
