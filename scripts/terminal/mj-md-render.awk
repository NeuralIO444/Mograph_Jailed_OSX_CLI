# Lightweight Markdown-to-terminal renderer for MographJailed help.
# Inputs are trusted local MJ help topics. No external package dependency.
BEGIN {
    code = 0
    ESC = sprintf("%c", 27)
    if (color == "1") {
        reset = ESC "[0m"
        blue = ESC "[38;2;88;166;255m"
        green = ESC "[38;2;63;185;80m"
        yellow = ESC "[38;2;210;153;34m"
        cyan = ESC "[38;2;57;197;207m"
        magenta = ESC "[38;2;188;140;255m"
        bold = ESC "[1m"
        dim = ESC "[2m"
    } else {
        reset = blue = green = yellow = cyan = magenta = bold = dim = ""
    }
}
function trimticks(s) {
    gsub(/`/, "", s)
    return s
}
/^```/ { code = !code; next }
code {
    print "    " cyan $0 reset
    next
}
/^### / {
    line = substr($0, 5)
    print "\n" magenta bold toupper(line) reset
    next
}
/^## / {
    line = substr($0, 4)
    print "\n" blue bold toupper(line) reset
    next
}
/^# / {
    line = substr($0, 3)
    print blue bold toupper(line) reset
    print blue "------------------------------------------------------------" reset
    next
}
/^- / {
    line = substr($0, 3)
    print "  " green "-" reset " " trimticks(line)
    next
}
/^> / {
    line = substr($0, 3)
    print yellow "  ! " reset trimticks(line)
    next
}
/^[[:space:]]*$/ { print ""; next }
{
    line = trimticks($0)
    print line
}
