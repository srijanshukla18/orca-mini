# Third-party notices

Orca Mini is derived from [Ora Browser](https://github.com/the-ora/browser) and contains work by its contributors. Ora Browser and Orca Mini are distributed under the GNU General Public License v3.0; see [LICENSE](LICENSE).

The versions below describe the dependency set resolved for Orca Mini 0.2.14. Update this file whenever a bundled dependency changes.

## Bundled components

| Component | Version | License | Copyright or source |
| --- | --- | --- | --- |
| [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) | 4.2.2 | GPL-3.0 | AdGuard Team and contributors |
| [FaviconFinder](https://github.com/will-lumley/FavIconFinder) | 5.1.5 | MIT | Copyright 2022 William Lumley |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | 2.13.9 | MIT | Copyright 2009-2025 Jonathan Hedley; copyright 2016-2025 Nabil Chatbi |
| [PunycodeSwift](https://github.com/gumob/PunycodeSwift) | 3.0.0 | MIT | Copyright 2018 Gumob |
| [swift-psl](https://github.com/ameshkov/swift-psl) | 1.1.164 | MIT | Copyright 2025 Andrey Meshkov |
| [Public Suffix List](https://publicsuffix.org/) data | Included by swift-psl | MPL-2.0 | [publicsuffix/list](https://github.com/publicsuffix/list) contributors |
| [SplitView](https://github.com/stevengharris/SplitView) | Vendored source | MIT | Copyright 2021 Steven Harris |
| [mark.js](https://markjs.io/) | 8.11.1 | MIT | Copyright 2014-2018 Julian Kühnel |

`swift-argument-parser` 1.5.0 is resolved as a build-time dependency of SafariConverterLib's command-line targets. It is not linked into the Orca Mini application target. Its source is licensed under Apache-2.0 with the Swift Runtime Library Exception.

SafariConverterLib is covered by the same GPLv3 text provided in [LICENSE](LICENSE). The Public Suffix List is available under the [Mozilla Public License 2.0](https://github.com/publicsuffix/list/blob/main/LICENSE). The Apache-2.0 text and Swift Runtime Library Exception are available in the [swift-argument-parser repository](https://github.com/apple/swift-argument-parser/blob/1.5.0/LICENSE.txt).

## MIT license text

The following terms apply to the MIT-licensed components listed above, together with each component's copyright notice.

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

The original license files in fetched Swift packages remain authoritative if this summary differs from them.
