"""Render the public main content as Markdown using only the Python standard library."""
from html.parser import HTMLParser
import re
from urllib.parse import urljoin


class MarkdownDocument(HTMLParser):
    def __init__(self, base_url):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.parts = []
        self.in_main = False
        self.skip_depth = 0
        self.links = []
        self.list_depth = 0
        self.in_pre = False

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'main':
            self.in_main = True
        if not self.in_main:
            return
        if self.skip_depth:
            if tag not in {'img', 'br', 'hr', 'input', 'source', 'meta', 'link'}:
                self.skip_depth += 1
            return
        if tag in {'script', 'style', 'svg'} or values.get('aria-hidden') == 'true':
            self.skip_depth = 1
            return
        if tag in {'section', 'div', 'p', 'figure', 'blockquote', 'details'}:
            self.parts.append('\n\n')
        elif re.fullmatch(r'h[1-6]', tag):
            self.parts.append('\n\n' + '#' * int(tag[1]) + ' ')
        elif tag in {'ul', 'ol'}:
            self.list_depth += 1
            self.parts.append('\n')
        elif tag == 'li':
            self.parts.append('\n' + '  ' * max(self.list_depth - 1, 0) + '- ')
        elif tag == 'a':
            self.links.append(urljoin(self.base_url, values.get('href', '')))
            self.parts.append('[')
        elif tag in {'strong', 'b'}:
            self.parts.append('**')
        elif tag == 'pre':
            self.in_pre = True
            self.parts.append('\n\n```\n')
        elif tag == 'code' and not self.in_pre:
            self.parts.append('`')
        elif tag == 'br':
            self.parts.append('\n')
        elif tag == 'img' and values.get('alt'):
            self.parts.append('![' + values['alt'] + '](' + urljoin(self.base_url, values.get('src', '')) + ')\n')
        elif tag == 'tr':
            self.parts.append('\n')
        elif tag in {'td', 'th'}:
            self.parts.append(' | ')

    def handle_endtag(self, tag):
        if not self.in_main:
            return
        if self.skip_depth:
            self.skip_depth -= 1
            return
        if tag == 'main':
            self.in_main = False
        elif tag == 'a' and self.links:
            self.parts.append('](' + self.links.pop() + ')')
        elif tag in {'strong', 'b'}:
            self.parts.append('** ')
        elif tag == 'pre':
            self.in_pre = False
            self.parts.append('\n```\n\n')
        elif tag == 'code' and not self.in_pre:
            self.parts.append('`')
        elif tag in {'ul', 'ol'}:
            self.list_depth = max(self.list_depth - 1, 0)
            self.parts.append('\n\n')
        elif tag in {'p', 'section', 'div', 'figure', 'blockquote', 'details', 'summary'} or re.fullmatch(r'h[1-6]', tag):
            self.parts.append('\n\n')

    def handle_data(self, data):
        if self.in_main and not self.skip_depth:
            self.parts.append(data if self.in_pre else re.sub(r'\s+', ' ', data))

    def markdown(self):
        lines = []
        fenced = False
        for line in ''.join(self.parts).splitlines():
            if line.strip() == '```':
                lines.append('```')
                fenced = not fenced
            elif fenced:
                lines.append(line)
            else:
                indent = line[:len(line) - len(line.lstrip())]
                content = re.sub(r'[ \t]+', ' ', line.strip())
                normalized = indent + content if content.startswith('- ') else content
                if normalized or (lines and lines[-1]):
                    lines.append(normalized)
        return '\n'.join(lines).strip() + '\n'
