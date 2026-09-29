MOGRAPHJAILED_PROTOCOL="MOGRAPHJAILED"
MOGRAPHJAILED_PROTOCOL_VERSION="1"
MOGRAPHJAILED_CLI_VERSION="0.3.0-dev.2"
MOGRAPHJAILED_STANDARD_LIBRARY_VERSION="1.0"
MOGRAPHJAILED_REQUEST_MAGIC="MOGRAPHJAILED_REQUEST"
MOGRAPHJAILED_REQUEST_VERSION="1"

# Normalize environment-sensitive native utility behavior. All production
# executable paths are absolute; PATH is retained only for child-tool hygiene.
LC_ALL=C
LANG=C
PATH=/usr/bin:/bin:/usr/sbin:/sbin
CDPATH=
COMMAND_MODE=unix2003
IFS=' 	
'
export LC_ALL LANG PATH CDPATH COMMAND_MODE IFS

# Prevent inherited macOS compatibility settings and startup/tool hooks from
# changing command behavior after the audited CLI starts. zsh -f also skips
# user startup files; /etc/zshenv remains an OS/IT-controlled target-Mac gate.
unset SYSTEM_VERSION_COMPAT 2>/dev/null || true
unset ENV BASH_ENV ZDOTDIR 2>/dev/null || true
unset DITTOABORT DITTONORSRC DITTOKEEPBINARIESPATTERN DITTOKEEPBINARIESDIR DITTO_TEST_OPTIONS 2>/dev/null || true
unset COPYFILE_DISABLE COPYFILE_PACK COPYFILE_UNPACK 2>/dev/null || true
unset PERL5OPT PERL5LIB PERLLIB PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT 2>/dev/null || true
unset SQLITE_HISTORY SQLITE_TMPDIR 2>/dev/null || true
