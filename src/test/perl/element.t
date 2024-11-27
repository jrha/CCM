# Test class Element

use strict;
use warnings;

use POSIX qw (getpid);
use DB_File;
use Digest::MD5 qw(md5_hex);
use Test::More;

use EDG::WP4::CCM::CacheManager qw ($DATA_DN $GLOBAL_LOCK_FN
                                    $CURRENT_CID_FN $LATEST_CID_FN);
use EDG::WP4::CCM::CacheManager::Configuration;
use EDG::WP4::CCM::CacheManager::Element;
use EDG::WP4::CCM::Path;
use LC::Exception;

use Cwd;

use CCMTest qw(make_file);

my $ec_cfg = $EDG::WP4::CCM::CacheManager::Configuration::ec;

my $cdtmp = getcwd()."/target/tmp";
mkdir($cdtmp) if (! -d $cdtmp);

#
# Generate an example of DBM file
#
sub gen_dbm ($$) {

    my ($cache_dir, $profile) = @_;
    my (%hash);
    my ($key, $val, $type, $active);

    # remove previous cache dir

    # create new profile
    mkdir("$cache_dir");
    mkdir("$cache_dir/$profile");
    mkdir("$cache_dir/$DATA_DN");

    make_file("$cache_dir/$GLOBAL_LOCK_FN", "no\n");
    make_file("$cache_dir/$CURRENT_CID_FN", "1\n");
    make_file("$cache_dir/$LATEST_CID_FN", "1\n");

    $active = $profile . "/active." . getpid();
    make_file("$cache_dir/$active", "1\n");

    tie(%hash, "DB_File", "${cache_dir}/${profile}/path2eid.db",
        &O_RDWR|&O_CREAT, 0644) or return();
    $key = "/path/to/property";
    $val = 0x00000001;
    $hash{$key} = pack("L", $val);
    $key = "/path/to/resource";
    $val = 0x00000002;
    $hash{$key} = pack("L", $val);
    untie(%hash);

    tie(%hash, "DB_File", "${cache_dir}/${profile}/eid2data.db",
        &O_RDWR|&O_CREAT, 0644) or return();
    # value
    $key = 0x00000001;
    $val = "a string";
    $hash{pack("L", $key)} = $val;
    # type
    $key = 0x10000001;
    $type = "string";
    $hash{pack("L", $key)} = $type;
    # checksum
    $key = 0x20000001;
    $hash{pack("L", $key)} = md5_hex("$val|$type");
    # description
    $key = 0x30000001;
    $hash{pack("L", $key)} = "an example of string";

    # value
    $key = 0x00000002;
    $val = "a list";
    $hash{pack("L", $key)} = $val;
    # type
    $key = 0x10000002;
    $type = "list";
    $hash{pack("L", $key)} = $type;
    # checksum
    $key = 0x20000002;
    $hash{pack("L", $key)} = md5_hex("$val|$type");
    # description
    $key = 0x30000002;
    $hash{pack("L", $key)} = "an example of list";

    untie(%hash);
}

my ($element, $property, $resource, $path);
my ($type, $checksum, $description, $value);
my ($string);

my ($cm, $config, $cache_dir, $profile);
my ($prof_dir, $eid, $name);


$cache_dir = "$cdtmp/cm-element-test";
$profile = "profile.1";
ok(! -d $cache_dir, "Cachedir $cache_dir doesn't exist");

# create profile
ok(gen_dbm($cache_dir, $profile), "creating an example profile for tests");

$cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
$config = EDG::WP4::CCM::CacheManager::Configuration->new($cm, 1, 1);

# create element with string path
$path = "/path/to/property";
$element = EDG::WP4::CCM::CacheManager::Element->new($config, $path);
isa_ok($element, "EDG::WP4::CCM::CacheManager::Element",
       "Element->new(config, string) is a EDG::WP4::CCM::CacheManager::Element instance");

# create element with Path object
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::CacheManager::Element->new($config, $path);
isa_ok($element, "EDG::WP4::CCM::CacheManager::Element",
       "Element->new(config, Path) is a EDG::WP4::CCM::CacheManager::Element instance");

# create resource with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/resource");
$element = EDG::WP4::CCM::CacheManager::Element->createElement($config, $path);
isa_ok($element, "EDG::WP4::CCM::CacheManager::Resource",
       "Element->createElement(config, Path_to_resource) is a EDG::WP4::CCM::CacheManager::Resource instance");

# create property Element with createElement()
$path = EDG::WP4::CCM::Path->new("/path/to/property");
$element = EDG::WP4::CCM::CacheManager::Element->createElement($config, $path);
isa_ok($element, "EDG::WP4::CCM::CacheManager::Element",
       "Element->createElement(config, Path_to_property) is a EDG::WP4::CCM::CacheManager::Element instance");
ok(!UNIVERSAL::isa($element, "EDG::WP4::CCM::CacheManager::Resource"),
   "Element->createElement(config, Path_to_property) is not a EDG::WP4::CCM::CacheManager::Resource instance");

# test getEID()
$eid = $element->getEID();
is($eid, 1, "Element->getEID() 1");

# test getName()
$name = $element->getName();
is($name, "property", "Element->getName()");

# test getPath()
$path = $element->getPath();
$string = $path->toString();
is($string, "/path/to/property", "Element->getPath()");

# test getType()
$type = $element->getType();
is($type, EDG::WP4::CCM::CacheManager::Element->STRING, "Element->getType()" );

# test getChecksum()
$checksum = $element->getChecksum();
is($checksum, md5_hex("a string|string"), "Element->getChecksum()");

# test getDescription()
$description = $element->getDescription();
is($description, "an example of string", "Element->getDescription()");

# test getValue()
$value = $element->getValue();
is($value, "a string", "Element->getValue()");

# test isType()
ok($element->isType(EDG::WP4::CCM::CacheManager::Element->STRING),
    "Element->isType(STRING)");
ok(!$element->isType(EDG::WP4::CCM::CacheManager::Element->LONG),
    "!Element->isType(LONG)");
ok(!$element->isType(EDG::WP4::CCM::CacheManager::Element->DOUBLE),
    "!Element->isType(DOUBLE)");
ok(!$element->isType(EDG::WP4::CCM::CacheManager::Element->BOOLEAN),
    "!Element->isType(BOOLEAN)");
ok(!$element->isType(EDG::WP4::CCM::CacheManager::Element->LIST),
    "!Element->isType(LIST)");
ok(!$element->isType(EDG::WP4::CCM::CacheManager::Element->NLIST),
    "!Element->isType(NLIST)");

# test isResource()
ok(!$element->isResource(),   "!Element->isResource()");

# test isProperty()
ok($element->isProperty(),   "Element->isProperty()");

#
# Test CCM::Configuration instance methods
#

# test getConfiguration()
$config = $element->getConfiguration();
$prof_dir  = $config->getConfigPath();
is($prof_dir, "$cache_dir/$profile", "Element->getConfiguration()");

$path = $element->getPath();

my $preppath = $config->_prepareElement("$path");
isa_ok($preppath, "EDG::WP4::CCM::Path",
       "_prepareElement returns EDG::WP4::CCM::Path instance");
is("$preppath", "$path", "_prepareElement path has expected value");

ok($config->elementExists("$path"), "config->elementExists true for path $path");
ok(! $config->elementExists("/fake$path"), "config->elementExists false for path /fake$path");

my $cfg_el = $config->getElement("$path");
my $pathdata = 'a string';

isa_ok($cfg_el, "EDG::WP4::CCM::CacheManager::Element",
       "config->getElement returns EDG::WP4::CCM::CacheManager::Element instance");
# is a property, not a hash or list
is($cfg_el->getValue(), $pathdata, "getVale from element instance as expected");
is_deeply($cfg_el->getTree(), $pathdata, "getTree from element instance as expected");

is($config->getValue("$path"), $pathdata, "config->getValue of $path as expected");
# is a property, not a hash or list
is_deeply($config->getTree("$path"), $pathdata, "config->getTree of $path as expected");

# Configuration::getTree error handling
# fail method
ok(! defined($config->{fail}), "No fail attribute set");
ok(! defined($config->fail("a", "b")), "Confiuration::fail returns undef");
is($config->{fail}, "ab", "Configuration fail attribute is set (joined args)");

# cfg->getTree does not throw errors
if ($ec_cfg->error()) {
    $ec_cfg->has_been_reported(1);
}
# reset fail attribute
$config->{fail} = undef;

ok(! $ec_cfg->error(), "No errors before testing getTree errorhandling");

ok(! defined($config->getTree("/fake$path")), "config->getTree of /fake$path undefined");
ok(! defined($config->{fail}),
   "config->getTree of /fake$path undefined does not set fail attribute (element does not exist)");

ok(! defined($config->getTree("//invalidpath")), "config->getTree of //invalidpath undefined");
like($config->{fail}, qr{path //invalidpath must be an absolute path},
   "config->getTree of //invalidpath undefined does sets fail attribute (invalid path throws error)");

ok(! $ec_cfg->error(), "No errors after testing getTree errorhandling");

# Inject an error, getTree should handle it gracefully (i.e. ignore it)
my $myerror = LC::Exception->new();
$myerror->is_error(1);
$ec_cfg->error($myerror);

ok($ec_cfg->error(), "Error before testing getTree errorhandling");
is_deeply($config->getTree("$path"), $pathdata, "config->getTree of $path as expected with existing error");
ok(! $ec_cfg->error(), "No errors after testing getTree errorhandling with existing error");


done_testing();
