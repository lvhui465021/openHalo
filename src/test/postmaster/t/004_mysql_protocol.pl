#!/usr/bin/perl

# 004_mysql_protocol.pl
#
# End-to-end test of the MySQL wire-protocol adapter.
# Starts a PostgreSQL node with both a standard PG listener (port chosen by
# PostgresNode) and a MySQL TCP listener (mysql.port).  Uses raw MySQL
# packets (pure Perl) to verify the handshake, mysql_native_password
# authentication, COM_QUERY, COM_PING, COM_QUIT, and the M2 parser
# pipeline through to the MySQL DestReceiver.
#
# This test does NOT require the mysql CLI — everything is driven at the
# wire level so that we can validate exact packet formats.

use strict;
use warnings;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# --- Helpers ----------------------------------------------------------

sub sha1 { require Digest::SHA; return Digest::SHA::sha1($_[0]); }

sub mysql_recv {
    my ($sock) = @_;
    my $buf = '';
    # Read exactly 4-byte header
    my $n = $sock->sysread($buf, 4);
    die "recv header: sysread returned " . (defined $n ? $n : 'undef') . ", err=$!"
        unless defined $n && $n == 4;
    my $plen = ord(substr($buf, 0, 1))
             | (ord(substr($buf, 1, 1)) << 8)
             | (ord(substr($buf, 2, 1)) << 16);
    my $remaining = $plen;
    while ($remaining > 0) {
        my $chunk = '';
        $n = $sock->sysread($chunk, $remaining);
        die "recv payload: need=$remaining, got " . (defined $n ? $n : 'undef') . ", err=$!"
            unless defined $n && $n > 0;
        $buf .= $chunk;
        $remaining -= $n;
    }
    return substr($buf, 4);  # return payload only
}

sub mysql_send_seq {
    my ($sock, $payload, $seq) = @_;
    my $plen = length($payload);
    my $hdr = pack('C3C', $plen & 0xFF, ($plen >> 8) & 0xFF, ($plen >> 16) & 0xFF, $seq);
    $sock->syswrite("$hdr$payload") == length($hdr) + $plen
        or die "send: $!";
}

# --- Setup ------------------------------------------------------------

my $node = PostgreSQL::Test::Cluster->new('mysql_protocol_test');
$node->init;
$node->start;

# Configure MySQL listener on a non-default port to avoid conflicts
my $mysql_port = 3308;
$node->append_conf('postgresql.conf', "mysql.listener_on = true");
$node->append_conf('postgresql.conf', "mysql.port = $mysql_port");
$node->append_conf('postgresql.conf', "mysql.backend_database = 'postgres'");
$node->append_conf('postgresql.conf', "listen_addresses = '127.0.0.1'");
# Kill any stale listener on 3308
system("fuser -k $mysql_port/tcp 2>/dev/null");
$node->restart;

# Give the MySQL listener a moment to bind
sleep 1;

# Create a MySQL-authenticated user (mysql_native_password)
my $pg_conn = $node->connstr('postgres');
$node->safe_psql('postgres', "CREATE USER mysql_user LOGIN PASSWORD 'test123';");
$node->safe_psql('postgres',
    "UPDATE pg_authid SET rolpassword = 'mysql_native_password:676243218923905cf94cb52a3c9d3eb30ce8e20d' WHERE rolname = 'mysql_user';");

# --- Connect with raw MySQL packets -----------------------------------

use IO::Socket::INET;
my $sock = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $mysql_port,
    Proto    => 'tcp',
    Timeout  => 10,
);
BAIL_OUT("cannot connect to MySQL listener on 127.0.0.1:$mysql_port: $!")
    unless $sock;
$sock->autoflush(1);

# -- Greeting --
my $greet = mysql_recv($sock);
ok(length($greet) >= 44, 'MySQL greeting packet received');
my $proto_ver = ord(substr($greet, 0, 1));
is($proto_ver, 10, 'protocol version 10');

# Extract full 20-byte scramble from the greeting
# Format: proto(1) + version(NUL) + thread_id(4) + part1(8) +
#         filler(1) + cap_lo(2) + charset(1) + status(2) + cap_hi(2) +
#         auth_data_len(1) + reserved(10) + part2(12) + plugin_name(NUL)
my $server_ver_end = index($greet, "\0", 5);
my $off = $server_ver_end + 1 + 4;
my $part1 = substr($greet, $off, 8);
$off += 8 + 1 + 2 + 1 + 2 + 2 + 1 + 10;
my $part2 = substr($greet, $off, 12);
my $challenge = $part1 . $part2;

# Sequence number after greeting: client sends at seq 1, then resets to 0 for commands
my $client_seq = 1;

# -- Auth: mysql_native_password --
my $p1 = sha1('test123');
my $token = $p1 ^ sha1($challenge . sha1($p1));

# Build login packet
my $caps = (1 | 512 | 32768 | 0x80000);
my $login = pack('V', $caps)               # client capabilities
          . pack('V', 0x00FFFFFF)            # max packet size
          . pack('C', 0x2D)                  # charset utf8mb4
          . ("\x00" x 23)                    # reserved
          . "mysql_user\x00"                 # username
          . pack('C', 20) . $token          # auth response
          . "mysql_native_password\x00";     # auth plugin name

mysql_send_seq($sock, $login, $client_seq);
my $auth_resp = mysql_recv($sock);
is(ord(substr($auth_resp, 0, 1)), 0x00, 'authentication OK');

# -- COM_QUERY: SELECT 1 --
mysql_send_seq($sock, "\x03SELECT 1", 0);
$client_seq = 1;
my $col_count_pkt = mysql_recv($sock);
my $first_byte = ord(substr($col_count_pkt, 0, 1));

# Parse column count.  If the first byte is 0x00 or 0x01 it could be
# the OPTIONAL_RESULTSET_METADATA metadata_follows flag (0 = no metadata,
# 1 = full metadata).  Otherwise it is the length-encoded column count
# directly (values < 251).
my $ncols;
if ($first_byte == 0 || $first_byte == 1) {
    # Could be metadata_follows flag; if so, the real column count follows
    if (length($col_count_pkt) > 1) {
        $ncols = ord(substr($col_count_pkt, 1, 1));
    } else {
        $ncols = $first_byte;
    }
} else {
    $ncols = $first_byte;
}
is($ncols, 1, 'SELECT 1 returns 1 column');

# Column definition
my $col_def = mysql_recv($sock);
ok(length($col_def) > 10, 'column definition received');

# Metadata EOF (skipped with DEPRECATE_EOF) or EOF present
# Read until we get a row or EOF/OK
my $row_or_eof = mysql_recv($sock);
my $first_byte = ord(substr($row_or_eof, 0, 1));

if ($first_byte == 0xFE && length($row_or_eof) < 9) {
    # Traditional EOF - read row next
    my $row = mysql_recv($sock);
    ok(length($row) >= 2, 'row data received');
    is(ord(substr($row, 1, 1)), ord('1'), "row contains '1'");
    # Final EOF
    my $final = mysql_recv($sock);
    ok(ord(substr($final, 0, 1)) == 0xFE || ord(substr($final, 0, 1)) == 0x00,
       'final EOF/OK received');
} elsif ($first_byte < 251) {
    # DEPRECATE_EOF: no metadata EOF, this IS the row
    ok($first_byte >= 1, 'row length >= 1');
    my $row_val = substr($row_or_eof, 1, $first_byte);
    is($row_val, '1', "row contains '1'");
    # Final OK (DEPRECATE_EOF style: 0xFE header)
    my $final = mysql_recv($sock);
    ok(ord(substr($final, 0, 1)) == 0xFE, 'final DEPRECATE_EOF OK received');
}

# -- COM_QUERY: SELECT 'hello' --
mysql_send_seq($sock, "\x03SELECT 'hello' AS greeting", 0);
$col_count_pkt = mysql_recv($sock);
$first_byte = ord(substr($col_count_pkt, 0, 1));
$ncols = ($first_byte == 0 || $first_byte == 1) ? ord(substr($col_count_pkt, -1, 1)) : $first_byte;
is($ncols, 1, "SELECT 'hello' returns 1 column");
$col_def = mysql_recv($sock);
ok(length($col_def) > 10, "column def for 'greeting'");

# Skip optional metadata EOF
$row_or_eof = mysql_recv($sock);
$first_byte = ord(substr($row_or_eof, 0, 1));
if ($first_byte == 0xFE && length($row_or_eof) < 9) {
    $row_or_eof = mysql_recv($sock);
    $first_byte = ord(substr($row_or_eof, 0, 1));
}
my $row_val = substr($row_or_eof, 1, $first_byte);
is($row_val, 'hello', "row contains 'hello'");
# Consume final EOF/OK
mysql_recv($sock);

# -- COM_PING --
mysql_send_seq($sock, "\x0E", 0);
my $ping_resp = mysql_recv($sock);
is(ord(substr($ping_resp, 0, 1)), 0x00, 'COM_PING returns OK');

# -- COM_QUIT --
mysql_send_seq($sock, "\x01", 0);
$sock->close();

# -- Verify PG side still works --
my $pg_result = $node->safe_psql('postgres', "SELECT 1 AS still_works;");
$pg_result =~ s/\s+$//;
is($pg_result, "1", 'PG standard connection still works after MySQL test');

done_testing();
