<script>alert(1)</script>

<img src="x" onerror="alert(1)" />

<svg onload="alert(1)"><circle cx="10" cy="10" r="5" /></svg>

<div onclick="alert(1)" style="background:url(javascript:alert(1))">Click</div>

GFM tagfilter elements: <title>x</title>, <textarea>x</textarea>, <style>body{}</style>, <xmp>x</xmp>, <iframe src="https://evil.example"></iframe>, <noembed>x</noembed>, <noframes>x</noframes>, <plaintext>x

<!-- --><script>alert(2)</script><!-- -->

Footnote XSS label[^"><script>alert(3)</script>].

[^"><script>alert(3)</script>]: payload body
