# MographJailed shell hookup: the one line the installer puts in ~/.zshrc sources this file.
# It loads the `mj` command and the help pages from wherever MographJailed is installed, so moving the
# install folder only means changing MOGRAPHJAILED_ROOT. Safe to source; it performs no work.
_mj_init_dir=${${(%):-%x}:A:h}
export MOGRAPHJAILED_ROOT="${MOGRAPHJAILED_ROOT:-${_mj_init_dir:h:h}}"
for _mj_init_f in mj-terminal mj-man mj-top mj-cli; do
    [ -r "$_mj_init_dir/$_mj_init_f.zsh" ] && source "$_mj_init_dir/$_mj_init_f.zsh"
done
unset _mj_init_dir _mj_init_f
