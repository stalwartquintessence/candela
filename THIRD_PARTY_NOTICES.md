# Third-party notices

## MonitorControl

Candela's Apple Silicon DDC/CI timing (double writes, reply delay, read offset, retry policy),
the IORegistry walk that pairs framebuffers with `DCPAVServiceProxy` services, and the idea of
gamma-table software dimming are adapted from
[MonitorControl](https://github.com/MonitorControl/MonitorControl), specifically
`MonitorControl/Support/Arm64DDC.swift` and `MonitorControl/Model/Display.swift`.
No MonitorControl source files are included verbatim.

```
MIT License

Copyright © 2017

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Apple SF Symbols

Window and indicator glyphs use SF Symbols through `NSImage(systemSymbolName:)`, which Apple permits in
apps running on Apple platforms. SF Symbols are not used in the app icon, which is original
artwork drawn by `scripts/IconRenderer.swift`.
