#!/bin/bash
#
# wf-clip — copy a Markdown file to the clipboard as rich text.
#
# Jira's editor (and Confluence, Google Docs, Slack, mail) keeps pasted Markdown
# as literal text: the headings stay as "###" and the lists as "- ". What they do
# format is HTML on the clipboard. This converts the Markdown the commands write
# (headings, paragraphs, nested and task lists, code spans and blocks, tables,
# links, quotes) to HTML and puts it on the clipboard as text/html, so a plain
# Ctrl+V pastes it formatted.
#
# Usage:
#   wf-clip.sh FILE                copy FILE as rich text
#   wf-clip.sh --drop-title FILE   leave the first heading out and print it, for
#                                  a ticket whose title goes in the Summary field
#   wf-clip.sh --html FILE         print the HTML instead of copying it
#   FILE can be - to read standard input.
#
# Clipboard: wl-copy (Wayland), xclip (X11) or textutil + pbcopy (macOS).
# Exit: 0 when copied or printed, 1 when the input is missing or no clipboard
# tool is available (the message says which one to install, or to use --html).

set -u

drop_title=0
print_html=0
file=""
for arg in "$@"; do
  case "$arg" in
    --drop-title) drop_title=1 ;;
    --html)       print_html=1 ;;
    -h|--help)    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -)            file="-" ;;
    -*)           echo "wf-clip: unknown option: $arg" >&2; exit 1 ;;
    *)            file="$arg" ;;
  esac
done

if [ -z "$file" ]; then
  echo "usage: wf-clip.sh [--drop-title] [--html] FILE|-" >&2
  exit 1
fi
if [ "$file" != "-" ] && [ ! -f "$file" ]; then
  echo "wf-clip: no such file: $file" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "wf-clip: python3 is required for the conversion" >&2
  exit 1
fi

src="$(mktemp)"; html_out="$(mktemp)"; title_out="$(mktemp)"
trap 'rm -f "$src" "$html_out" "$title_out"' EXIT
if [ "$file" = "-" ]; then cat > "$src"; else cat "$file" > "$src"; fi

read -r -d '' CONVERTER << 'PY'
import html, re, sys

src_path, drop_title, title_path = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
lines = open(src_path, encoding="utf-8").read().splitlines()

if drop_title:
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        m = re.match(r"^#{1,6}\s+(.*)$", line)
        if m:
            open(title_path, "w", encoding="utf-8").write(m.group(1).strip())
            del lines[i]
        break

def inline(text):
    out = []
    for part in re.split(r"(`[^`]+`)", text):
        if len(part) > 1 and part.startswith("`") and part.endswith("`"):
            out.append("<code>%s</code>" % html.escape(part[1:-1], quote=False))
            continue
        part = html.escape(part, quote=False)
        # Bare URLs first; one right after "(" or "[" belongs to a [text](url) link.
        part = re.sub(r"(?<![(\[])(https?://[^\s<()\[\]]+[^\s<()\[\].,;:])",
                      r'<a href="\1">\1</a>', part)
        part = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                      lambda m: '<a href="%s">%s</a>' % (m.group(2).replace('"', "&quot;"), m.group(1)), part)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])", r"<em>\1</em>", part)
        out.append(part)
    return "".join(out)

LIST = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")

out, para, item = [], [], []
stack = []          # open lists: [indent, tag, content_indent]
after_blank = False

def flush_para():
    if para:
        out.append("<p>%s</p>" % inline(" ".join(s.strip() for s in para)))
        para.clear()

def flush_item():
    if item:
        out.append(inline(" ".join(s.strip() for s in item)))
        item.clear()

def close_lists(above=-1):
    flush_item()
    while stack and stack[-1][0] > above:
        out.append("</li></%s>" % stack.pop()[1])

def cells(row):
    row = row.strip()
    if row.startswith("|"): row = row[1:]
    if row.endswith("|"): row = row[:-1]
    return [c.strip() for c in row.split("|")]

i = 0
while i < len(lines):
    line = lines[i]
    indent = len(line) - len(line.lstrip())

    if not line.strip():
        flush_para(); flush_item()
        after_blank = True
        i += 1
        continue

    # A line that is neither a list item nor indented under the open item ends the list.
    m = LIST.match(line)
    if stack and not m and indent < stack[-1][2]:
        close_lists()

    if FENCE.match(line):
        flush_para(); flush_item()
        fence, code = line.strip()[:3], []
        i += 1
        while i < len(lines) and not lines[i].strip().startswith(fence):
            code.append(lines[i][indent:] if lines[i][:indent].strip() == "" else lines[i])
            i += 1
        out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(code), quote=False))
        i += 1
        after_blank = False
        continue

    if m:
        flush_para()
        ind, marker, box, text = len(m.group(1)), m.group(2), m.group(3), m.group(4)
        tag = "ul" if marker in "-*+" else "ol"
        close_lists(ind)
        if stack and stack[-1][0] == ind and stack[-1][1] == tag:
            flush_item()
            out.append("</li><li>")
        else:
            if stack and stack[-1][0] == ind:
                close_lists(ind - 1)
            out.append("<%s><li>" % tag)
            stack.append([ind, tag, ind + len(marker) + 1])
        if box:
            text = ("☑ " if box[1] in "xX" else "☐ ") + text
        item.append(text)
        after_blank = False
        i += 1
        continue

    if stack:
        # Continuation of the open item; after a blank line it is a new paragraph in it.
        if after_blank:
            flush_item()
            out.append("<br><br>")
        item.append(line)
        after_blank = False
        i += 1
        continue

    h = re.match(r"^(#{1,6})\s+(.*)$", line)
    if h:
        flush_para()
        n = len(h.group(1))
        out.append("<h%d>%s</h%d>" % (n, inline(h.group(2).strip()), n))
    elif re.match(r"^\s*([-*_])(\s*\1){2,}\s*$", line):
        flush_para()
        out.append("<hr>")
    elif line.lstrip().startswith(">"):
        flush_para()
        quote = []
        while i < len(lines) and lines[i].lstrip().startswith(">"):
            quote.append(lines[i].lstrip()[1:].strip())
            i += 1
        out.append("<blockquote><p>%s</p></blockquote>" % inline(" ".join(quote)))
        continue
    elif line.lstrip().startswith("|") and i + 1 < len(lines) and TABLE_SEP.match(lines[i + 1]):
        flush_para()
        rows = ["<tr>%s</tr>" % "".join("<th>%s</th>" % inline(c) for c in cells(line))]
        i += 2
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            rows.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in cells(lines[i])))
            i += 1
        out.append("<table>%s</table>" % "".join(rows))
        continue
    else:
        para.append(line)
    after_blank = False
    i += 1

flush_para()
close_lists()
sys.stdout.write('<meta charset="utf-8">' + "\n".join(out) + "\n")
PY

python3 -I -c "$CONVERTER" "$src" "$drop_title" "$title_out" > "$html_out" || exit 1

if [ "$print_html" -eq 1 ]; then
  cat "$html_out"
  [ -s "$title_out" ] && echo "Title (left out): $(cat "$title_out")" >&2
  exit 0
fi

if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
  wl-copy --type text/html < "$html_out"
elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard -t text/html < "$html_out"
elif command -v pbcopy >/dev/null 2>&1 && command -v textutil >/dev/null 2>&1; then
  # The macOS pasteboard takes rich text as RTF; textutil converts the HTML.
  textutil -stdin -format html -convert rtf -stdout < "$html_out" | pbcopy
else
  echo "wf-clip: no clipboard tool found (install wl-clipboard on Wayland or xclip on X11)," >&2
  echo "         or print the HTML with --html" >&2
  exit 1
fi

if [ -s "$title_out" ]; then
  echo "Title (left out of the clipboard): $(cat "$title_out")"
fi
echo "Copied as rich text — paste with Ctrl+V (Ctrl+Shift+V pastes it as plain text)."
