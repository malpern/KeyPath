# Third-Party Licenses

KeyPath includes the following third-party software:

---

## Kanata

**Project:** https://github.com/jtroo/kanata
**Author:** jtroo
**License:** LGPL-3.0 (GNU Lesser General Public License v3.0)

Kanata is a cross-platform keyboard remapping engine that powers KeyPath's core functionality. KeyPath bundles a modified version of Kanata as a separate executable.

The full LGPL-3.0 license text is available at:
https://www.gnu.org/licenses/lgpl-3.0.html

In accordance with LGPL-3.0 Section 4 (Combined Works):
- The Kanata source code used by KeyPath is available at: https://github.com/malpern/KeyPath/tree/master/External/kanata
- Users may replace the bundled Kanata binary with their own version
- KeyPath's Swift source code is licensed separately under MIT

---

## Karabiner VirtualHID Driver

**Project:** https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
**Author:** pqrs.org
**License:** Public Domain

The Karabiner Virtual HID Driver creates a virtual keyboard device that KeyPath uses to output remapped keys.

---

## License Compliance

KeyPath (the Swift application code) is released under the MIT License.

The bundled Kanata binary is licensed under LGPL-3.0. This is a "Combined Work" as defined by the LGPL. You have the right to:
- Modify the Kanata portions
- Replace the bundled Kanata binary with your own build
- Access the complete Kanata source code

For questions about licensing, please open an issue at:
https://github.com/malpern/KeyPath/issues
