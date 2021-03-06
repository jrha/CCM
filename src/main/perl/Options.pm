#${PMpre} EDG::WP4::CCM::Options${PMpost}

use CAF::Application qw($OPTION_CFGFILE);
use CAF::Reporter;
use LC::Exception qw(SUCCESS);
use EDG::WP4::CCM::CCfg qw(@CONFIG_OPTIONS $CONFIG_FN setCfgValue);
use EDG::WP4::CCM::Path qw(escape);
use EDG::WP4::CCM::CacheManager;
use Readonly;

use parent qw(CAF::Application CAF::Reporter);

Readonly::Hash my %PATH_SELECTION_METHODS => {
    profpath => {
        help => 'profile path',
        method => sub { return $_[0]; },
    },
    component => {
        help => 'component',
        method => sub { return "/software/components/". $_[0]; },
    },
    metaconfig => {
        help => 'metaconfig service',
        method => sub { return "/software/components/metaconfig/services/". escape($_[0]) . "/contents"; },
    },
};


# Default module actions
Readonly::Hash my %ACTIONS => {
    showcids => 'Show valid CIDs',
};

# hashref with actions that are supported via the action method
# Default use all ACTIONS. Modify via add_actions method
my $_actions = { %ACTIONS };
# Default action
my $_default_action;

=head1 NAME

EDG::WP4::CCM::Options

=head1 DESCRIPTION

Use this module to create (commandline) application that interact with CCM directly.

Available convenience methods:

=over

=cut


# initialize
sub _initialize
{
    my $self = shift;

    # version and usage
    $self->{'VERSION'} = "${project.version}";
    $self->{'USAGE'}   = sprintf("Usage: %s [OPTIONS...]", $0);

    # initialise
    unless ($self->SUPER::_initialize(@_)) {
        return;
    }

    return SUCCESS;
}

=item app_options

Return list of CCM application specific options and
commandline options for all CCM config options

=cut

sub app_options
{

    my @options = (
        {
            # the ccm client will use the main ccm.conf from CCfg
            NAME    => "$OPTION_CFGFILE=s",
            DEFAULT => $CONFIG_FN,
            HELP    => 'Configuration file for CCM',
        },

        {
            NAME    => "cid=s",
            HELP    => "Set configuration CID (default 'undef' is the current CID; see CCM::CacheManager getCid for special values)",
        },

    );

    # Actions
    foreach my $act (sort keys %$_actions) {
        push(@options, {
             NAME => "$act",
             HELP => $_actions->{$act},
             });
    }

    # profile path selection options
    foreach my $sel (sort keys %PATH_SELECTION_METHODS) {
        push(@options, {
             NAME => "$sel=s@",
             HELP => "Select the ".$PATH_SELECTION_METHODS{$sel}->{help}."(s)",
             });
    }

    # Add support for all CCfg CONFIG_OPTIONS
    foreach my $opt (@CONFIG_OPTIONS) {
        # don't modify the original hasrefs
        my $newopt = {
            NAME => $opt->{option},
            HELP => $opt->{HELP},
        };

        $newopt->{NAME} .= $opt->{suffix} if exists($opt->{suffix});
        $newopt->{DEFAULT} .= $opt->{DEFAULT} if exists($opt->{DEFAULT});

        push(@options, $newopt);
    }

    return \@options;
}


=item setCCMConfig

Set the CCM Configuration instance for CID C<cid> under CCM_CONFIG attribute
using CacheManager's C<getConfiguration> method.

If C<cid> is not defined, the C<cid> value from the C<--cid>-option will be used.
(To use the current CID when another cid value set via C<--cid>-option, pass an empty
string or the string 'current').

A CacheManager instance under CACHEMGR attribute is created if none exists
or C<force_cache> is set to true.

Returns SUCCESS on success, undef on failure.

=cut

sub setCCMConfig
{
    my ($self, $cid, $force_cache) = @_;

    my $msg;

    if((! defined($self->{CACHEMGR})) || $force_cache) {
        my $configfile = $self->option($OPTION_CFGFILE);
        my $cacheroot = $self->option('cache_root');

        # The CCM::CacheManager->new() does CCfg::initCfg
        # but we need to pass/redefine the relevant commandline options too.
        # TODO: what a mess
        # TODO: is there a way to only set the values defined on commandline?
        foreach my $opt (@CONFIG_OPTIONS) {
            my $option = $opt->{option};
            # force them to protect against (re)reading (e.g. in Fetch)
            setCfgValue($option, $self->option($option), 1);
        }

        $msg = "cache manager with cacheroot $cacheroot and configfile $configfile";
        $self->verbose("Accessing CCM $msg.");
        $self->{CACHEMGR} = EDG::WP4::CCM::CacheManager->new($cacheroot, $configfile);
        unless (defined $self->{'CACHEMGR'}) {
            throw_error ("Cannot access $msg.");
            return;
        }
    }

    $cid = $self->option('cid') if(! defined($cid));

    $msg = "for CID ". (defined($cid) ? $cid : "<undef>");
    $self->verbose("getting CCM configuration $msg.");
    $self->{CCM_CONFIG} = $self->{CACHEMGR}->getConfiguration(undef, $cid);
    unless (defined $self->{CCM_CONFIG}) {
        throw_error ("Cannot get configuration via CCM $msg.");
        return;
    }

    return SUCCESS;
}

=item getCCMConfig

Returns the CCM configuration instance.
If none exists, one is created via C<setCCMConfig> method.

All arguments are passed to possible C<setCCMConfig> call.

=cut

sub getCCMConfig
{
    my $self = shift;

    $self->setCCMConfig(@_) if(! defined($self->{CCM_CONFIG}));

    return $self->{CCM_CONFIG};
}

=item gatherPaths

Retrun arrayref of selected profile path (via the PATH_SELECTION_METHODS)

All options are treated as initial paths.

=cut

sub gatherPaths
{
    my ($self, @paths) = @_;

    if (@paths) {
        $self->debug(4, 'Initial paths passed: ', join(',', @paths));
    } else {
        $self->debug(4, 'No initial paths');
    }

    # profile path selection options
    foreach my $sel (sort keys %PATH_SELECTION_METHODS) {
        my $values = $self->option($sel);
        my $method = $PATH_SELECTION_METHODS{$sel}->{method};
        if (defined($values)) {
            foreach my $val (@$values) {
                push(@paths, $method->($val))
            }
        }
    }
    $self->debug(4, "gatherPaths ", join(",", @paths));
    return \@paths;
}

# wrapper around report (for easy unittesting)
sub _print
{
    my ($self, @args) = @_;
    $self->report(@args);
}

=item default_action

Set the default action C<$action> if action is defined
(use empty string to unset the default value).

Returns the default action.

=cut

sub default_action
{
    my ($self, $action) = @_;

    if(defined($action)) {
        if(($action eq '') || $self->can("action_$action")) {
            $self->verbose("Set default action to $action.");
            $_default_action = $action;
        } else {
            $self->warn("Not adding non-existing action $action as default action.");
        }
    }

    return $_default_action;
}


=item action_showcids

the showcids action prints all sorted profile CIDs as comma-separated list

=cut

sub action_showcids
{
    my $self = shift;

    $self->setCCMConfig();

    my $cids = $self->{CACHEMGR}->getCids();

    $self->_print(join(',', @$cids), "\n");

    return SUCCESS;
}

=item add_actions

Add actions defined in hashref to the supported actions.

When creating a new module derived from EDG::WP4::CCM::Options,
add methods named "action_<something>", and add then via this method
to the _actions hashref.

This will create a commandline option "--something", if selected,
will execute the action_<something> method.

The hashref key is the action name, the value is the help text.

(Returns the _actions hashref for unittesting purposes)

=cut

sub add_actions
{
    my ($self, $newactions) = @_;

    while (my ($action, $help) = each %$newactions) {
        if($self->can("action_$action")) {
            $_actions->{$action} = $help;
        } else {
            $self->warn("Not adding non-existing action $action");
        }
    }

    return $_actions;
}

=item action

Run first of the predefined actions via the action_<actionname> methods

=cut

sub action
{
    my $self = shift;

    # defined actions
    my @acts = grep {$self->option($_)} sort keys %$_actions;
    my $act;

    # very primitive for now: run first found
    if (@acts && $acts[0] =~ m/^(\w+)$/) {
        $act = $1;
    }

    if ($act) {
        $self->debug(5, "Selected ", ($act || "<undef>"),
                     " from actions ", join(",", @acts));
    } else {
        $act = $self->default_action();
        if ($act) {
            $self->debug(5, "Selected default action $act");
        } else {
            $self->verbose("No action set. Doin nothing")
        }
    }

    if ($act) {
        my $method = $self->can("action_$act");
        if($method) {
            # execute it
            my $res = $method->($self);
            $self->debug(3, "Method for action $act returned undef") if (! defined($res));
            return $res;
        } else {
            $self->debug(3, "No method for action $act found");
            return;
        }
    }

    # return SUCCESS if no actions selected (nothing goes wrong)
    return SUCCESS;
}

=pod

=back

=cut


1;
