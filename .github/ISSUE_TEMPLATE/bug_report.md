---
name: Bug report
about: Something does not work with your display
labels: bug
---

**What happened**

**What you expected**

**Your setup**
- Mac model and chip (Apple menu > About This Mac):
- macOS version:
- Monitor make and model:
- Connection (which Mac port, cable or adapter, any dock or hub):
- Is DDC/CI enabled in the monitor's on-screen menu?

**Diagnostics**

Please paste the output of these commands (they only read from the display):

```
/Applications/Candela.app/Contents/MacOS/candelactl info
/Applications/Candela.app/Contents/MacOS/candelactl probe --verbose
```

You can also use "Copy Report" on Candela's Display Info page. Remove the serial number if
you prefer not to share it.
